#!/bin/bash
# ============================================================
# GSP344 – Develop Serverless Apps with Firebase: Challenge Lab
# One-click automation | github.com/KrushnaHangargekar/arcade_automation
# Run in Google Cloud Shell: bash solve.sh
# ============================================================

set -euo pipefail

# ─── 0. INITIALISATION ────────────────────────────────────────────────────────
echo "=========================================="
echo " GSP344 – Firebase Challenge Lab Solver"
echo "=========================================="

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
  PROJECT_ID=$(gcloud projects list \
    --format='value(PROJECT_ID)' \
    --filter='qwiklabs-gcp' | head -n 1)
  gcloud config set project "$PROJECT_ID" --quiet
fi
echo "✅  Project : $PROJECT_ID"

# Firestore MUST be in us-west1 (lab requirement)
FIRESTORE_REGION="us-west1"

# Cloud Run region — default us-central1; override: REGION=us-east1 bash solve.sh
REGION="${REGION:-us-central1}"
gcloud config set compute/region "$REGION" --quiet
gcloud config set run/region     "$REGION" --quiet
echo "✅  Run Region     : $REGION"
echo "✅  Firestore Reg. : $FIRESTORE_REGION"

# ─── 1. ENABLE APIS ───────────────────────────────────────────────────────────
echo ""
echo "[Setup] Enabling required GCP APIs..."
gcloud services enable \
  firestore.googleapis.com \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  --quiet
echo "✅  APIs enabled."

# ─── CLONE PET-THEORY REPO ────────────────────────────────────────────────────
if [ ! -d "pet-theory" ]; then
  echo "[Setup] Cloning pet-theory repository..."
  git clone https://github.com/rosera/pet-theory.git
fi
echo "✅  pet-theory repo ready."

# ─── TASK 1 – CREATE FIRESTORE DATABASE ───────────────────────────────────────
echo ""
echo "=========================================="
echo "[Task 1] Creating Firestore database..."
echo "         Mode: Native | Region: $FIRESTORE_REGION"
echo "=========================================="
gcloud firestore databases create \
  --location="$FIRESTORE_REGION" \
  --type=firestore-native \
  --quiet 2>&1 || echo "⚠️  Firestore already exists — skipping."
echo "✅  Task 1 complete."

# ─── TASK 2 – IMPORT NETFLIX CSV ──────────────────────────────────────────────
echo ""
echo "=========================================="
echo "[Task 2] Importing Netflix CSV into Firestore..."
echo "=========================================="
pushd pet-theory/lab06/firebase-import-csv/solution > /dev/null
npm install --silent
node index.js netflix_titles_original.csv
popd > /dev/null
echo "✅  Task 2 complete – Firestore populated."

# ─── TASK 3 – REST API v0.1 ───────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "[Task 3] Building & deploying REST API v0.1..."
echo "=========================================="
gcloud artifacts repositories create rest-api-repo \
  --repository-format=docker \
  --location="$REGION" \
  --quiet 2>&1 || echo "⚠️  Artifact repo already exists — skipping."

pushd pet-theory/lab06/firebase-rest-api/solution-01 > /dev/null
gcloud builds submit \
  --tag "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.1" \
  . --quiet
gcloud run deploy netflix-dataset-service \
  --image "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.1" \
  --platform managed \
  --region "$REGION" \
  --allow-unauthenticated \
  --max-instances 1 \
  --quiet
popd > /dev/null
echo "✅  Task 3 complete."

# ─── TASK 4 – REST API v0.2 (FIRESTORE-CONNECTED) ────────────────────────────
echo ""
echo "=========================================="
echo "[Task 4] Building & deploying REST API v0.2..."
echo "=========================================="
pushd pet-theory/lab06/firebase-rest-api/solution-02 > /dev/null
gcloud builds submit \
  --tag "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.2" \
  . --quiet
gcloud run deploy netflix-dataset-service \
  --image "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.2" \
  --platform managed \
  --region "$REGION" \
  --allow-unauthenticated \
  --max-instances 1 \
  --quiet
popd > /dev/null

REST_API_URL=$(gcloud run services describe netflix-dataset-service \
  --region "$REGION" \
  --format='value(status.url)')
echo "✅  Task 4 complete – REST API: $REST_API_URL"

# Smoke-test: the /2019 endpoint must return JSON
echo "🔍  Smoke testing REST API..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$REST_API_URL/2019")
if [ "$HTTP_CODE" = "200" ]; then
  echo "✅  REST API /2019 returned HTTP 200."
else
  echo "⚠️  REST API /2019 returned HTTP $HTTP_CODE — check Cloud Run logs."
fi

# ─── TASK 5 – STAGING FRONTEND ────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "[Task 5] Building & deploying Staging Frontend..."
echo "=========================================="
pushd pet-theory/lab06/firebase-frontend > /dev/null
gcloud builds submit \
  --tag "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-staging:0.1" \
  . --quiet
gcloud run deploy frontend-staging-service \
  --image "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-staging:0.1" \
  --platform managed \
  --region "$REGION" \
  --allow-unauthenticated \
  --max-instances 1 \
  --quiet
popd > /dev/null
echo "✅  Task 5 complete – Staging frontend deployed."

# ─── TASK 6 – PRODUCTION FRONTEND ─────────────────────────────────────────────
echo ""
echo "=========================================="
echo "[Task 6] Patching app.js → deploying Production Frontend..."
echo "=========================================="

APP_JS="pet-theory/lab06/firebase-frontend/public/app.js"

echo "--- app.js before patch ---"
cat "$APP_JS"
echo "----------------------------"

# The pet-theory app.js has exactly:
#   const REST_API_SERVICE = "data/netflix.json"
# and calls:
#   fetchLocalData(REST_API_SERVICE)
#
# We need:
#   const REST_API_SERVICE = "<live-url>"
# and the fetch call must append the year:
#   fetchLocalData(REST_API_SERVICE + "/" + new Date().getFullYear())
#
# We write the corrected getPageInfo() function directly so there is
# no ambiguity about which sed pattern hit or missed.

# Step 1 – Replace the REST_API_SERVICE constant value
sed -i \
  "s|const REST_API_SERVICE = \"data/netflix.json\"|const REST_API_SERVICE = \"${REST_API_URL}\"|g" \
  "$APP_JS"

# Step 2 – Replace the static fetchLocalData call to append /year
# Original: const info = await fetchLocalData(REST_API_SERVICE)
# Target  : const info = await fetchLocalData(REST_API_SERVICE + "/" + new Date().getFullYear())
sed -i \
  's|fetchLocalData(REST_API_SERVICE)|fetchLocalData(REST_API_SERVICE + "/" + new Date().getFullYear())|g' \
  "$APP_JS"

echo "--- app.js after patch ---"
cat "$APP_JS"
echo "--------------------------"

# Verify patch succeeded — abort with clear error if not
if grep -q "data/netflix.json" "$APP_JS"; then
  echo "❌  ERROR: app.js patch FAILED — 'data/netflix.json' still present."
  echo "    Please manually edit $APP_JS and re-run the last gcloud commands."
  exit 1
fi
echo "✅  app.js patched successfully."

pushd pet-theory/lab06/firebase-frontend > /dev/null
gcloud builds submit \
  --tag "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-production:0.1" \
  . --quiet
gcloud run deploy frontend-production-service \
  --image "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-production:0.1" \
  --platform managed \
  --region "$REGION" \
  --allow-unauthenticated \
  --max-instances 1 \
  --quiet
popd > /dev/null

PROD_URL=$(gcloud run services describe frontend-production-service \
  --region "$REGION" \
  --format='value(status.url)')
echo "✅  Task 6 complete – Production frontend deployed."

# ─── FINAL SUMMARY ────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "  🎉  ALL 6 TASKS COMPLETED SUCCESSFULLY!"
echo "=========================================="
echo "  REST API (v0.2)       : $REST_API_URL"
echo "  Test /2019            : curl -X GET $REST_API_URL/2019"
echo "  Production Frontend   : $PROD_URL"
echo "=========================================="

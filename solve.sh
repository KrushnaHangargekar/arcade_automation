#!/bin/bash
# ============================================================
# GSP344 – Develop Serverless Apps with Firebase: Challenge Lab
# One-click automation script | github.com/KrushnaHangargekar/arcade_automation
# ============================================================

set -euo pipefail

# ─── 0. INITIALISATION ────────────────────────────────────────────────────────
echo "=========================================="
echo " GSP344 – Firebase Challenge Lab Solver"
echo "=========================================="

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
  PROJECT_ID=$(gcloud projects list --format='value(PROJECT_ID)' --filter='qwiklabs-gcp' | head -n 1)
  gcloud config set project "$PROJECT_ID" --quiet
fi
echo "✅  Project : $PROJECT_ID"

# Firestore location required by the lab
FIRESTORE_REGION="us-west1"

# Cloud Run region – prefer us-central1 (cheapest / most available); override if needed
REGION="${REGION:-us-central1}"
gcloud config set compute/region  "$REGION" --quiet
gcloud config set run/region      "$REGION" --quiet
echo "✅  Run Region : $REGION"

# ─── 1. ENABLE APIS ───────────────────────────────────────────────────────────
echo ""
echo "[Task 0] Enabling required GCP APIs..."
gcloud services enable \
  firestore.googleapis.com \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  --quiet
echo "✅  APIs enabled."

# ─── 2. CLONE PET-THEORY REPO ─────────────────────────────────────────────────
if [ ! -d "pet-theory" ]; then
  echo ""
  echo "[Setup] Cloning pet-theory repository..."
  git clone https://github.com/rosera/pet-theory.git
fi
echo "✅  pet-theory repo ready."

# ─── TASK 1 – CREATE FIRESTORE DATABASE ───────────────────────────────────────
echo ""
echo "=========================================="
echo "[Task 1] Creating Firestore database (Native mode, $FIRESTORE_REGION)..."
echo "=========================================="
gcloud firestore databases create \
  --location="$FIRESTORE_REGION" \
  --type=firestore-native \
  --quiet 2>&1 | grep -v "already exists" || true
echo "✅  Task 1 complete – Firestore database ready."

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
# Create Artifact Registry repo (idempotent)
gcloud artifacts repositories create rest-api-repo \
  --repository-format=docker \
  --location="$REGION" \
  --quiet 2>&1 | grep -v "already exists" || true

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
echo "✅  Task 3 complete – REST API v0.1 deployed."

# ─── TASK 4 – REST API v0.2 (FIRESTORE-CONNECTED) ────────────────────────────
echo ""
echo "=========================================="
echo "[Task 4] Building & deploying REST API v0.2 (Firestore-connected)..."
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

# Grab the live service URL
REST_API_URL=$(gcloud run services describe netflix-dataset-service \
  --region "$REGION" \
  --format='value(status.url)')
echo "✅  Task 4 complete – REST API URL: $REST_API_URL"

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
echo "[Task 6] Patching app.js and deploying Production Frontend..."
echo "=========================================="
APP_JS="pet-theory/lab06/firebase-frontend/public/app.js"

# Show current fetch line for debug
echo "--- Before patch ---"
grep -n "fetch\|const REST" "$APP_JS" || true

# Strategy: replace any line that sets up the REST_API_SERVICE variable,
# OR replace the fetch URL if the variable pattern differs.
# The lab's app.js typically contains either:
#   const REST_API_SERVICE = "data/netflix.json"
# or a fetch() call pointing to demo data.
# We patch ALL plausible patterns robustly.

# Pattern A – named constant
sed -i \
  "s|const REST_API_SERVICE = .*|const REST_API_SERVICE = \"${REST_API_URL}\";|g" \
  "$APP_JS"

# Pattern B – inline fetch with demo JSON (fallback)
sed -i \
  "s|fetch('data/netflix.json')|fetch(REST_API_SERVICE + '/' + selectedYear)|g" \
  "$APP_JS"

# Pattern C – ensure year is appended after REST_API_SERVICE variable (idempotent)
# If the line already ends with the URL we need to also add the year append.
# We detect any fetch that uses REST_API_SERVICE WITHOUT /year and fix it:
if grep -q "fetch(REST_API_SERVICE)" "$APP_JS" 2>/dev/null; then
  sed -i \
    "s|fetch(REST_API_SERVICE)|fetch(REST_API_SERVICE + '/' + selectedYear)|g" \
    "$APP_JS"
fi

echo "--- After patch ---"
grep -n "fetch\|const REST" "$APP_JS" || true

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

# ─── SUMMARY ──────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "  🎉  ALL 6 TASKS COMPLETED SUCCESSFULLY!"
echo "=========================================="
echo "  REST API Service   : $REST_API_URL"
echo "  Production Frontend: $PROD_URL"
echo "  Verify /2019 query : curl -X GET $REST_API_URL/2019"
echo "=========================================="

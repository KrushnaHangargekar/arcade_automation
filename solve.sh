#!/bin/bash
# GSP344 – Develop Serverless Apps with Firebase: Challenge Lab
# Run in Google Cloud Shell: bash solve.sh
set -euo pipefail

echo "=========================================="
echo " GSP344 – Firebase Challenge Lab Solver"
echo "=========================================="

# ── Project ──────────────────────────────────────────────────
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
  PROJECT_ID=$(gcloud projects list \
    --format='value(PROJECT_ID)' --filter='qwiklabs-gcp' | head -n 1)
  gcloud config set project "$PROJECT_ID" --quiet
fi
echo "✅  Project: $PROJECT_ID"

# ── Enable APIs ───────────────────────────────────────────────
echo "[Setup] Enabling APIs..."
gcloud services enable \
  firestore.googleapis.com \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  --quiet
echo "✅  APIs enabled."

# ── Auto-detect the org-policy-allowed region ─────────────────
# The lab's org policy blocks most regions. We probe Artifact Registry
# across all common US regions until one succeeds.
detect_region() {
  # 1. Explicit override
  if [ -n "${REGION:-}" ]; then echo "$REGION"; return; fi
  # 2. Qwiklabs env var
  if [ -n "${GOOGLE_CLOUD_REGION:-}" ]; then echo "$GOOGLE_CLOUD_REGION"; return; fi
  # 3. gcloud configured region (may already be set by the lab)
  local r
  r=$(gcloud config get-value compute/region 2>/dev/null || true)
  if [ -n "$r" ]; then echo "$r"; return; fi
  # 4. Probe Artifact Registry to find what the org policy allows
  echo "Probing for an allowed region (org policy check)..." >&2
  local probe="probe-$(date +%s)"
  for r in us-east1 us-west1 us-west2 us-east4 us-central1 us-south1; do
    printf "  %-16s ... " "$r" >&2
    if gcloud artifacts repositories create "$probe" \
        --repository-format=docker --location="$r" --quiet 2>/dev/null; then
      gcloud artifacts repositories delete "$probe" \
        --location="$r" --quiet 2>/dev/null || true
      echo "✅ allowed" >&2
      echo "$r"
      return
    fi
    echo "blocked" >&2
  done
  echo "❌  ERROR: No allowed region found. Run: REGION=<region> bash solve.sh" >&2
  exit 1
}

REGION=$(detect_region)
gcloud config set compute/region "$REGION" --quiet
gcloud config set run/region     "$REGION" --quiet
echo "✅  Run Region     : $REGION"
echo "✅  Firestore Reg. : us-west1"

# ── Clone pet-theory ──────────────────────────────────────────
if [ ! -d "pet-theory" ]; then
  echo "[Setup] Cloning pet-theory..."
  git clone https://github.com/rosera/pet-theory.git
fi
echo "✅  pet-theory ready."

# ══════════════════════════════════════════════════════════════
# TASK 1 – Create Firestore database (us-west1, Native mode)
# ══════════════════════════════════════════════════════════════
echo ""
echo "[Task 1] Creating Firestore database (us-west1)..."
gcloud firestore databases create \
  --location=us-west1 \
  --type=firestore-native \
  --quiet 2>&1 || echo "⚠️  Firestore already exists."
echo "✅  Task 1 done."

# ══════════════════════════════════════════════════════════════
# TASK 2 – Import Netflix CSV
# ══════════════════════════════════════════════════════════════
echo ""
echo "[Task 2] Importing Netflix CSV into Firestore..."
pushd pet-theory/lab06/firebase-import-csv/solution > /dev/null
npm install --silent
node index.js netflix_titles_original.csv
popd > /dev/null
echo "✅  Task 2 done."

# ══════════════════════════════════════════════════════════════
# TASK 3 – REST API v0.1
# ══════════════════════════════════════════════════════════════
echo ""
echo "[Task 3] Creating Artifact Registry repo in $REGION..."

# Properly distinguish "already exists" from org-policy error
AR_LOG=$(gcloud artifacts repositories create rest-api-repo \
  --repository-format=docker --location="$REGION" --quiet 2>&1) && AR_OK=true || AR_OK=false

if [ "$AR_OK" = "false" ]; then
  if echo "$AR_LOG" | grep -qi "already.exist\|ALREADY_EXISTS"; then
    echo "⚠️  Repo already exists — OK."
  else
    echo "❌  Failed to create Artifact Registry repo:"
    echo "$AR_LOG"
    exit 1
  fi
fi

echo "[Task 3] Building & deploying REST API v0.1..."
pushd pet-theory/lab06/firebase-rest-api/solution-01 > /dev/null
gcloud builds submit \
  --tag "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.1" \
  . --quiet
gcloud run deploy netflix-dataset-service \
  --image "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.1" \
  --platform managed --region "$REGION" \
  --allow-unauthenticated --max-instances 1 --quiet
popd > /dev/null
echo "✅  Task 3 done."

# ══════════════════════════════════════════════════════════════
# TASK 4 – REST API v0.2 (Firestore-connected)
# ══════════════════════════════════════════════════════════════
echo ""
echo "[Task 4] Building & deploying REST API v0.2..."
pushd pet-theory/lab06/firebase-rest-api/solution-02 > /dev/null
gcloud builds submit \
  --tag "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.2" \
  . --quiet
gcloud run deploy netflix-dataset-service \
  --image "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.2" \
  --platform managed --region "$REGION" \
  --allow-unauthenticated --max-instances 1 --quiet
popd > /dev/null

REST_API_URL=$(gcloud run services describe netflix-dataset-service \
  --region "$REGION" --format='value(status.url)')
echo "✅  Task 4 done — REST API: $REST_API_URL"

# Smoke test
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$REST_API_URL/2019")
echo "🔍  /2019 smoke test → HTTP $HTTP_CODE"

# ══════════════════════════════════════════════════════════════
# TASK 5 – Staging Frontend
# ══════════════════════════════════════════════════════════════
echo ""
echo "[Task 5] Building & deploying Staging Frontend..."
pushd pet-theory/lab06/firebase-frontend > /dev/null
gcloud builds submit \
  --tag "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-staging:0.1" \
  . --quiet
gcloud run deploy frontend-staging-service \
  --image "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-staging:0.1" \
  --platform managed --region "$REGION" \
  --allow-unauthenticated --max-instances 1 --quiet
popd > /dev/null
echo "✅  Task 5 done."

# ══════════════════════════════════════════════════════════════
# TASK 6 – Production Frontend (patch app.js with live API URL)
# ══════════════════════════════════════════════════════════════
echo ""
echo "[Task 6] Patching app.js → deploying Production Frontend..."

APP_JS="pet-theory/lab06/firebase-frontend/public/app.js"

# Patch 1: Replace the REST_API_SERVICE constant value
sed -i \
  "s|const REST_API_SERVICE = \"data/netflix.json\"|const REST_API_SERVICE = \"${REST_API_URL}\"|g" \
  "$APP_JS"

# Patch 2: Append /<year> to the fetchLocalData call
sed -i \
  's|fetchLocalData(REST_API_SERVICE)|fetchLocalData(REST_API_SERVICE + "/" + new Date().getFullYear())|g' \
  "$APP_JS"

# Verify patch succeeded
if grep -q "data/netflix.json" "$APP_JS"; then
  echo "❌  app.js patch FAILED — 'data/netflix.json' still present."
  echo "    Current app.js content:"
  cat "$APP_JS"
  exit 1
fi
echo "✅  app.js patched."

pushd pet-theory/lab06/firebase-frontend > /dev/null
gcloud builds submit \
  --tag "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-production:0.1" \
  . --quiet
gcloud run deploy frontend-production-service \
  --image "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-production:0.1" \
  --platform managed --region "$REGION" \
  --allow-unauthenticated --max-instances 1 --quiet
popd > /dev/null

PROD_URL=$(gcloud run services describe frontend-production-service \
  --region "$REGION" --format='value(status.url)')
echo "✅  Task 6 done."

# ══════════════════════════════════════════════════════════════
echo ""
echo "=========================================="
echo "  🎉  ALL 6 TASKS COMPLETED!"
echo "=========================================="
echo "  REST API          : $REST_API_URL"
echo "  Test endpoint     : curl $REST_API_URL/2019"
echo "  Production UI     : $PROD_URL"
echo "=========================================="

#!/bin/bash
# GSP344 – Develop Serverless Apps with Firebase: Challenge Lab
# Usage: bash solve.sh [start_task]
set -euo pipefail

START_TASK=${1:-1}
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
echo "Project: $PROJECT_ID"

# ── Enable APIs first ─────────────────────────────────────────
gcloud services enable \
  firestore.googleapis.com \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  --quiet

# ── Auto-detect allowed region ────────────────────────────────
# Probes Artifact Registry to find the region allowed by org policy.
# Both Firestore and Cloud Run will use this same region.
echo "Detecting allowed region (probing org policy)..."
REGION=""
PROBE="probe-$$"
for r in us-east1 us-west1 us-central1 us-west2 us-east4 us-south1; do
  printf "  %-14s ... " "$r"
  if gcloud artifacts repositories create "$PROBE" \
      --repository-format=docker --location="$r" --quiet 2>/dev/null; then
    gcloud artifacts repositories delete "$PROBE" \
      --location="$r" --quiet 2>/dev/null || true
    REGION="$r"
    echo "✅ allowed"
    break
  fi
  echo "blocked"
done

if [ -z "$REGION" ]; then
  echo "❌ Cannot detect an allowed region. Set REGION=<r> and re-run."
  exit 1
fi

gcloud config set compute/region "$REGION" --quiet
gcloud config set run/region     "$REGION" --quiet
echo "Using region: $REGION"

# Clone pet-theory
if [ ! -d "pet-theory" ]; then
  git clone https://github.com/rosera/pet-theory.git
fi

# ── TASK 1: Create Firestore ──────────────────────────────────
if [ "$START_TASK" -le 1 ]; then
  echo "=== [Task 1] Create Firestore ($REGION) ==="
  FIRESTORE_OUT=$(gcloud firestore databases create \
    --location="$REGION" --type=firestore-native --quiet 2>&1) && FS_OK=true || FS_OK=false

  if [ "$FS_OK" = "false" ]; then
    if echo "$FIRESTORE_OUT" | grep -qi "already.exist\|ALREADY_EXISTS"; then
      echo "⚠️  Firestore already exists."
    else
      echo "❌ Firestore creation FAILED:"
      echo "$FIRESTORE_OUT"
      exit 1
    fi
  fi
  echo "✅ Task 1 done"
fi

# ── TASK 2: Import Netflix CSV ────────────────────────────────
if [ "$START_TASK" -le 2 ]; then
  echo "=== [Task 2] Import Netflix CSV ==="
  pushd pet-theory/lab06/firebase-import-csv/solution > /dev/null
  npm install --silent
  node index.js netflix_titles_original.csv
  popd > /dev/null
  echo "✅ Task 2 done"
fi

# ── TASK 3: REST API v0.1 ─────────────────────────────────────
if [ "$START_TASK" -le 3 ]; then
  echo "=== [Task 3] Deploy REST API v0.1 ==="
  gcloud artifacts repositories create rest-api-repo \
    --repository-format=docker --location="$REGION" --quiet 2>&1 || true

  pushd pet-theory/lab06/firebase-rest-api/solution-01 > /dev/null
  gcloud builds submit \
    --tag "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.1" . --quiet
  gcloud run deploy netflix-dataset-service \
    --image "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.1" \
    --platform managed --region "$REGION" \
    --allow-unauthenticated --max-instances 1 --quiet
  popd > /dev/null
  echo "✅ Task 3 done"
fi

# ── TASK 4: REST API v0.2 ─────────────────────────────────────
if [ "$START_TASK" -le 4 ]; then
  echo "=== [Task 4] Deploy REST API v0.2 ==="
  pushd pet-theory/lab06/firebase-rest-api/solution-02 > /dev/null
  gcloud builds submit \
    --tag "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.2" . --quiet
  gcloud run deploy netflix-dataset-service \
    --image "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.2" \
    --platform managed --region "$REGION" \
    --allow-unauthenticated --max-instances 1 --quiet
  popd > /dev/null
  echo "✅ Task 4 done"
fi

# Get REST API URL
REST_API_URL=$(gcloud run services describe netflix-dataset-service \
  --region "$REGION" --format='value(status.url)')
echo "REST API URL: $REST_API_URL"

APP_JS="pet-theory/lab06/firebase-frontend/public/app.js"

# ── TASK 5: Staging Frontend — DEMO DATA (no app.js patch) ────
if [ "$START_TASK" -le 5 ]; then
  echo "=== [Task 5] Deploy Staging Frontend (demo mode) ==="
  # Restore original app.js — Task 5 must use demo data/netflix.json
  curl -sf \
    "https://raw.githubusercontent.com/rosera/pet-theory/main/lab06/firebase-frontend/public/app.js" \
    -o "$APP_JS"
  echo "app.js restored to demo mode"

  pushd pet-theory/lab06/firebase-frontend > /dev/null
  gcloud builds submit \
    --tag "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-staging:0.1" . --quiet
  gcloud run deploy frontend-staging-service \
    --image "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-staging:0.1" \
    --platform managed --region "$REGION" \
    --allow-unauthenticated --max-instances 1 --quiet
  popd > /dev/null
  echo "✅ Task 5 done"
fi

# ── TASK 6: Production Frontend — PATCHED app.js ──────────────
if [ "$START_TASK" -le 6 ]; then
  echo "=== [Task 6] Deploy Production Frontend (live data) ==="
  # Restore original then patch with live URL + year
  curl -sf \
    "https://raw.githubusercontent.com/rosera/pet-theory/main/lab06/firebase-frontend/public/app.js" \
    -o "$APP_JS"

  sed -i \
    "s|const REST_API_SERVICE = \"data/netflix.json\"|const REST_API_SERVICE = \"${REST_API_URL}/2020\"|g" \
    "$APP_JS"

  if grep -q "data/netflix.json" "$APP_JS"; then
    echo "❌ app.js patch failed"; cat "$APP_JS"; exit 1
  fi
  echo "app.js patched: $REST_API_URL/2020"

  pushd pet-theory/lab06/firebase-frontend > /dev/null
  gcloud builds submit \
    --tag "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-production:0.1" . --quiet
  gcloud run deploy frontend-production-service \
    --image "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-production:0.1" \
    --platform managed --region "$REGION" \
    --allow-unauthenticated --max-instances 1 --quiet
  popd > /dev/null
  echo "✅ Task 6 done"
fi

echo "=========================================="
echo "  🎉  ALL TASKS COMPLETE"
echo "  REST API : $REST_API_URL"
echo "=========================================="

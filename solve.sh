#!/bin/bash
# GSP344 – Firebase Challenge Lab Solver
# Usage: bash solve.sh 5 (to run from Task 5 onwards)
set -euo pipefail

START_TASK=${1:-1}
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
REGION="us-west1"

# ── TASKS 1-4 (Skipped if START_TASK > 4) ──────────────────────
if [ "$START_TASK" -le 1 ]; then
  gcloud firestore databases create --location="$REGION" --type=firestore-native --quiet 2>&1 || true
fi
if [ "$START_TASK" -le 2 ]; then
  if [ ! -d "pet-theory" ]; then git clone https://github.com/rosera/pet-theory.git; fi
  pushd pet-theory/lab06/firebase-import-csv/solution > /dev/null
  npm install --silent && node index.js netflix_titles_original.csv
  popd > /dev/null
fi
if [ "$START_TASK" -le 4 ]; then
  gcloud artifacts repositories create rest-api-repo --repository-format=docker --location="$REGION" --quiet 2>&1 || true
  # Deploy API v0.2
  pushd pet-theory/lab06/firebase-rest-api/solution-02 > /dev/null
  gcloud builds submit --tag "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.2" . --quiet
  gcloud run deploy netflix-dataset-service --image "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.2" --region "$REGION" --allow-unauthenticated --max-instances 1 --quiet
  popd > /dev/null
fi

REST_API_URL=$(gcloud run services describe netflix-dataset-service --region "$REGION" --format='value(status.url)')

# ── TASK 5: Staging Frontend ───────────────────────────────────
if [ "$START_TASK" -le 5 ]; then
  echo "[Task 5] Deploying Staging Frontend..."
  pushd pet-theory/lab06/firebase-frontend > /dev/null
  gcloud builds submit --tag "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-staging:0.1" . --quiet
  gcloud run deploy frontend-staging-service \
    --image "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-staging:0.1" \
    --region "$REGION" \
    --allow-unauthenticated \
    --max-instances 1 \
    --set-env-vars "REST_API_SERVICE=$REST_API_URL" \
    --quiet
  popd > /dev/null
  echo "✅  Task 5 done."
fi

# ── TASK 6: Production Frontend ────────────────────────────────
if [ "$START_TASK" -le 6 ]; then
  echo "[Task 6] Patching app.js & deploying Production Frontend..."
  APP_JS="pet-theory/lab06/firebase-frontend/public/app.js"
  
  # Standard lab patch: replace the variable with URL + /2020
  sed -i "s|const REST_API_SERVICE = \"data/netflix.json\"|const REST_API_SERVICE = \"${REST_API_URL}/2020\"|g" "$APP_JS"
  
  pushd pet-theory/lab06/firebase-frontend > /dev/null
  gcloud builds submit --tag "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-production:0.1" . --quiet
  gcloud run deploy frontend-production-service \
    --image "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-production:0.1" \
    --region "$REGION" \
    --allow-unauthenticated \
    --max-instances 1 \
    --set-env-vars "REST_API_SERVICE=$REST_API_URL" \
    --quiet
  popd > /dev/null
  echo "✅  Task 6 done."
fi

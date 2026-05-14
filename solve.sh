#!/bin/bash
# GSP344 – Firebase Challenge Lab Solver
# Usage: 
#   bash solve.sh       (Runs all tasks)
#   bash solve.sh 4     (Starts from Task 4)
set -euo pipefail

START_TASK=${1:-1}

echo "=========================================="
echo " GSP344 – Resume from Task $START_TASK"
echo "=========================================="

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
REGION="us-west1" # Required for Firestore GSP344
gcloud config set compute/region "$REGION" --quiet
gcloud config set run/region     "$REGION" --quiet

# ── TASK 1: Firestore ──────────────────────────────────────────
if [ "$START_TASK" -le 1 ]; then
  echo "[Task 1] Creating Firestore..."
  gcloud firestore databases create --location="$REGION" --type=firestore-native --quiet 2>&1 || true
fi

# ── TASK 2: Import CSV ─────────────────────────────────────────
if [ "$START_TASK" -le 2 ]; then
  echo "[Task 2] Importing CSV..."
  if [ ! -d "pet-theory" ]; then git clone https://github.com/rosera/pet-theory.git; fi
  pushd pet-theory/lab06/firebase-import-csv/solution > /dev/null
  npm install --silent
  node index.js netflix_titles_original.csv
  popd > /dev/null
fi

# ── TASK 3: REST API v0.1 ──────────────────────────────────────
if [ "$START_TASK" -le 3 ]; then
  echo "[Task 3] Deploying REST API v0.1..."
  gcloud artifacts repositories create rest-api-repo --repository-format=docker --location="$REGION" --quiet 2>&1 || true
  pushd pet-theory/lab06/firebase-rest-api/solution-01 > /dev/null
  gcloud builds submit --tag "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.1" . --quiet
  gcloud run deploy netflix-dataset-service --image "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.1" --region "$REGION" --allow-unauthenticated --max-instances 1 --quiet
  popd > /dev/null
fi

# ── TASK 4: REST API v0.2 ──────────────────────────────────────
if [ "$START_TASK" -le 4 ]; then
  echo "[Task 4] Updating REST API to v0.2..."
  pushd pet-theory/lab06/firebase-rest-api/solution-02 > /dev/null
  gcloud builds submit --tag "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.2" . --quiet
  gcloud run deploy netflix-dataset-service --image "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.2" --region "$REGION" --allow-unauthenticated --max-instances 1 --quiet
  popd > /dev/null
fi

REST_API_URL=$(gcloud run services describe netflix-dataset-service --region "$REGION" --format='value(status.url)')

# ── TASK 5: Staging Frontend ───────────────────────────────────
if [ "$START_TASK" -le 5 ]; then
  echo "[Task 5] Deploying Staging Frontend..."
  git checkout pet-theory/lab06/firebase-frontend/public/app.js || true
  pushd pet-theory/lab06/firebase-frontend > /dev/null
  gcloud builds submit --tag "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-staging:0.1" . --quiet
  gcloud run deploy frontend-staging-service --image "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-staging:0.1" --region "$REGION" --allow-unauthenticated --max-instances 1 --quiet
  popd > /dev/null
fi

# ── TASK 6: Production Frontend ────────────────────────────────
if [ "$START_TASK" -le 6 ]; then
  echo "[Task 6] Patching app.js & deploying Production Frontend..."
  APP_JS="pet-theory/lab06/firebase-frontend/public/app.js"
  sed -i "s|const REST_API_SERVICE = \"data/netflix.json\"|const REST_API_SERVICE = \"${REST_API_URL}/2020\"|g" "$APP_JS"
  pushd pet-theory/lab06/firebase-frontend > /dev/null
  gcloud builds submit --tag "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-production:0.1" . --quiet
  gcloud run deploy frontend-production-service --image "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-production:0.1" --region "$REGION" --allow-unauthenticated --max-instances 1 --quiet
  popd > /dev/null
fi

echo "=========================================="
echo " ✅ Tasks completed from $START_TASK to 6"
echo "=========================================="

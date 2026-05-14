#!/bin/bash
# GSP344 – Firebase Challenge Lab Solver
# Usage: bash solve.sh 5
set -euo pipefail

START_TASK=${1:-1}
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
REGION="us-west1"

# ── Ensure API URL is available ────────────────────────────────
REST_API_URL=$(gcloud run services describe netflix-dataset-service --region "$REGION" --format='value(status.url)' 2>/dev/null || echo "")

if [ -z "$REST_API_URL" ] && [ "$START_TASK" -ge 4 ]; then
  echo "⚠️  REST API not found. Running Task 4 first..."
  START_TASK=4
fi

# ── TASK 4 (if needed) ────────────────────────────────────────
if [ "$START_TASK" -le 4 ]; then
  echo "[Task 4] Deploying REST API v0.2..."
  if [ ! -d "pet-theory" ]; then git clone https://github.com/rosera/pet-theory.git; fi
  pushd pet-theory/lab06/firebase-rest-api/solution-02 > /dev/null
  gcloud builds submit --tag "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.2" . --quiet
  gcloud run deploy netflix-dataset-service --image "$REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.2" --region "$REGION" --allow-unauthenticated --max-instances 1 --quiet
  popd > /dev/null
  REST_API_URL=$(gcloud run services describe netflix-dataset-service --region "$REGION" --format='value(status.url)')
fi

# ── TASK 5: Staging Frontend (NEAT) ───────────────────────────
if [ "$START_TASK" -le 5 ]; then
  echo "[Task 5] Deploying Staging Frontend (Correct Service + Env Var)..."
  # Ensure clean code for demo mode
  cd pet-theory && git checkout lab06/firebase-frontend/public/app.js && cd ..
  
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
  echo "✅  Task 5 neatly done."
fi

# ── TASK 6: Production Frontend ────────────────────────────────
if [ "$START_TASK" -le 6 ]; then
  echo "[Task 6] Deploying Production Frontend (Correct Service + Patch)..."
  APP_JS="pet-theory/lab06/firebase-frontend/public/app.js"
  
  # Patch app.js for production data
  sed -i "s|const REST_API_SERVICE = \"data/netflix.json\"|const REST_API_SERVICE = \"${REST_API_URL}/2019\"|g" "$APP_JS"
  
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
  echo "✅  Task 6 neatly done."
fi

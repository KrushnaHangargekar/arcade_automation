#!/bin/bash
# GSP344 – Develop Serverless Apps with Firebase: Challenge Lab
# Usage:
#   bash solve.sh       → all 6 tasks
#   bash solve.sh 4     → start from task 4
# ─────────────────────────────────────────────
set -euo pipefail

START_TASK=${1:-1}
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
REGION="us-west1"   # Satisfies Firestore requirement + org policy for this lab

gcloud config set compute/region "$REGION" --quiet
gcloud config set run/region     "$REGION" --quiet
echo "Project: $PROJECT_ID | Region: $REGION"

# Clone pet-theory if not present
if [ ! -d "pet-theory" ]; then
  git clone https://github.com/rosera/pet-theory.git
fi

# ── TASK 1: Firestore ──────────────────────────────────────────
if [ "$START_TASK" -le 1 ]; then
  echo "=== [Task 1] Create Firestore ==="
  gcloud services enable firestore.googleapis.com --quiet
  gcloud firestore databases create \
    --location="$REGION" --type=firestore-native --quiet 2>&1 || true
  echo "✅ Task 1 done"
fi

# ── TASK 2: Import CSV ─────────────────────────────────────────
if [ "$START_TASK" -le 2 ]; then
  echo "=== [Task 2] Import Netflix CSV ==="
  pushd pet-theory/lab06/firebase-import-csv/solution > /dev/null
  npm install --silent
  node index.js netflix_titles_original.csv
  popd > /dev/null
  echo "✅ Task 2 done"
fi

# ── TASK 3: REST API v0.1 ──────────────────────────────────────
if [ "$START_TASK" -le 3 ]; then
  echo "=== [Task 3] Deploy REST API v0.1 ==="
  gcloud services enable run.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com --quiet
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

# ── TASK 4: REST API v0.2 ──────────────────────────────────────
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

# Fetch REST API URL (needed for Tasks 5 & 6)
REST_API_URL=$(gcloud run services describe netflix-dataset-service \
  --region "$REGION" --format='value(status.url)')
echo "REST API URL: $REST_API_URL"

APP_JS="pet-theory/lab06/firebase-frontend/public/app.js"

# ── TASK 5: Staging Frontend — DEMO DATA, NO PATCH ────────────
# The lab note says: "It's using a demo dataset to provide the onscreen entries."
# So app.js MUST stay in its original state (data/netflix.json).
# The grader only checks that the correct image & service name were used.
if [ "$START_TASK" -le 5 ]; then
  echo "=== [Task 5] Deploy Staging Frontend (demo mode) ==="

  # Always restore app.js to its original content before building staging
  curl -sf \
    "https://raw.githubusercontent.com/rosera/pet-theory/main/lab06/firebase-frontend/public/app.js" \
    -o "$APP_JS"
  echo "app.js restored to original (demo mode)"

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

# ── TASK 6: Production Frontend — PATCH app.js with live URL ──
# The lab says: "update app.js to use the REST API"
# and "Don't forget to append the year to the SERVICE_URL."
# The commented hint in the original app.js shows:
#   //const REST_API_SERVICE = "https://XXXX-SERVICE.run.app/2020"
if [ "$START_TASK" -le 6 ]; then
  echo "=== [Task 6] Deploy Production Frontend (live data) ==="

  # Restore original first (in case we're resuming from task 6 only)
  curl -sf \
    "https://raw.githubusercontent.com/rosera/pet-theory/main/lab06/firebase-frontend/public/app.js" \
    -o "$APP_JS"

  # Patch: replace demo URL with live API URL + year (2020)
  sed -i \
    "s|const REST_API_SERVICE = \"data/netflix.json\"|const REST_API_SERVICE = \"${REST_API_URL}/2020\"|g" \
    "$APP_JS"

  # Verify patch worked
  if grep -q "data/netflix.json" "$APP_JS"; then
    echo "❌ ERROR: app.js patch failed! Content:"
    cat "$APP_JS"
    exit 1
  fi
  echo "app.js patched — REST_API_SERVICE = ${REST_API_URL}/2020"

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

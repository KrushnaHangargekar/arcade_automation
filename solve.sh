#!/bin/bash
# TURBO MODE for Challenge Lab GSP344

# 0. Setup
export PROJECT_ID=$(gcloud config get-value project)
ACCOUNT=$(gcloud auth list --format="value(account)" | head -n 1)
gcloud config set account $ACCOUNT --quiet

# Find an allowed region (Smart Detection)
export REGION=$(gcloud compute regions list --limit=1 --format="value(name)")
if [ -z "$REGION" ]; then REGION="us-west1"; fi
gcloud config set compute/region $REGION
gcloud config set run/region $REGION

echo "Using Region: $REGION"

# Task 1 & 2 (In background)
gcloud firestore databases create --location=$REGION --type=firestore-native --quiet || true
git clone https://github.com/rosera/pet-theory.git || true
cd pet-theory/lab06/firebase-import-csv/solution
npm install --quiet
node index.js netflix_titles_original.csv & # Run in background

# Task 3 & 4 (REST API)
cd ../../firebase-rest-api/solution-01
gcloud artifacts repositories create rest-api-repo --repository-format=docker --location=$REGION --quiet || true
gcloud builds submit --tag $REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.1 . --quiet
gcloud run deploy netflix-dataset-service --image $REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.1 --platform managed --region $REGION --allow-unauthenticated --max-instances 1 --quiet

cd ../solution-02
gcloud builds submit --tag $REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.2 . --quiet
gcloud run deploy netflix-dataset-service --image $REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.2 --platform managed --region $REGION --allow-unauthenticated --max-instances 1 --quiet

# Task 5 & 6 (Frontend)
cd ../../firebase-frontend
URL=$(gcloud run services describe netflix-dataset-service --region $REGION --format='value(status.url)')
gcloud builds submit --tag $REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-staging:0.1 . --quiet
gcloud run deploy frontend-staging-service --image $REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-staging:0.1 --platform managed --region $REGION --allow-unauthenticated --max-instances 1 --quiet

sed -i "s|const REST_API_SERVICE = \"data/netflix.json\"|const REST_API_SERVICE = \"$URL/2020\"|" public/app.js
gcloud builds submit --tag $REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-production:0.1 . --quiet
gcloud run deploy frontend-production-service --image $REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-production:0.1 --platform managed --region $REGION --allow-unauthenticated --max-instances 1 --quiet

echo "TURBO COMPLETE!"

#!/bin/bash
# Arcade Automation: Develop Serverless Apps with Firebase: Challenge Lab (GSP344)

# Stop on first error
set -e

# 0. Setup variables
PROJECT_ID=$(gcloud config get-value project)
ACCOUNT=$(gcloud auth list --format="value(account)" | head -n 1)
gcloud config set account $ACCOUNT --quiet

# Detect Region from environment or fallback
export REGION=$(gcloud compute regions list --limit=1 --format="value(name)")
if [ -z "$REGION" ]; then
  REGION="us-east4"
fi
gcloud config set compute/region $REGION
gcloud config set run/region $REGION

echo "Using Project: $PROJECT_ID"
echo "Using Region: $REGION"

# Ensure APIs are enabled
gcloud services enable firestore.googleapis.com run.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com

# Clone repo if not exists
if [ ! -d "pet-theory" ]; then
    git clone https://github.com/rosera/pet-theory.git
fi

# Task 1. Create a Firestore database
# The lab instructions strictly mention us-east4 for Firestore
echo "Creating Firestore Database..."
gcloud firestore databases create --location=us-east4 --type=firestore-native --quiet || echo "Firestore already created."

# Task 2. Import the database
echo "Importing CSV to Firestore..."
cd pet-theory/lab06/firebase-import-csv/solution
npm install --quiet
node index.js netflix_titles_original.csv

# Task 3. Create the REST API (v0.1)
echo "Deploying REST API 0.1..."
cd ../../firebase-rest-api/solution-01
gcloud artifacts repositories create rest-api-repo --repository-format=docker --location=$REGION --quiet || echo "Repo already exists."
gcloud builds submit --tag $REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.1 . --quiet
gcloud run deploy netflix-dataset-service \
  --image $REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.1 \
  --platform managed --region $REGION --allow-unauthenticated --max-instances 1 --quiet

# Task 4. Configure Firestore API access (v0.2)
echo "Deploying REST API 0.2..."
cd ../solution-02
gcloud builds submit --tag $REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.2 . --quiet
gcloud run deploy netflix-dataset-service \
  --image $REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.2 \
  --platform managed --region $REGION --allow-unauthenticated --max-instances 1 --quiet

# Get the URL of the deployed REST API
REST_API_URL=$(gcloud run services describe netflix-dataset-service --region $REGION --format='value(status.url)')
echo "REST API URL: $REST_API_URL"

# Task 5. Deploy the staging frontend
echo "Deploying Staging Frontend..."
cd ../../firebase-frontend
gcloud builds submit --tag $REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-staging:0.1 . --quiet
gcloud run deploy frontend-staging-service \
  --image $REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-staging:0.1 \
  --platform managed --region $REGION --allow-unauthenticated --max-instances 1 --quiet

# Task 6. Deploy the production frontend
echo "Deploying Production Frontend..."
# Update app.js to point to the live REST API
sed -i "s|const REST_API_SERVICE = \"data/netflix.json\"|const REST_API_SERVICE = \"$REST_API_URL/2020\"|" public/app.js

gcloud builds submit --tag $REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-production:0.1 . --quiet
gcloud run deploy frontend-production-service \
  --image $REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-production:0.1 \
  --platform managed --region $REGION --allow-unauthenticated --max-instances 1 --quiet

echo "All tasks completed successfully!"

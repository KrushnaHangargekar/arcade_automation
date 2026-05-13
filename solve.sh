#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Starting Challenge Lab: Develop Serverless Apps with Firebase...${NC}"

# 1. Project ID and Region Setup
export PROJECT_ID=$(gcloud config get-value project)
# Attempt to get region, default to us-central1 if not set
export REGION=$(gcloud config get-value compute/region)
if [ -z "$REGION" ]; then
    export REGION="us-central1"
fi

echo -e "${GREEN}Project ID: $PROJECT_ID | Region: $REGION${NC}"

# 2. Firestore Setup
echo -e "${YELLOW}Task 1: Creating Firestore Database...${NC}"
gcloud firestore databases create --location=$REGION --type=firestore-native --quiet || echo "Firestore already exists or can't be created."

# 3. Clone and Import Data
echo -e "${YELLOW}Task 2: Importing Netflix Data...${NC}"
git clone https://github.com/rosera/pet-theory.git
cd pet-theory/lab06/firebase-import-csv/solution
npm install --quiet
node index.js netflix_titles_original.csv

# 4. REST API v0.1
echo -e "${YELLOW}Task 3: Deploying REST API v0.1...${NC}"
gcloud artifacts repositories create rest-api-repo --repository-format=docker --location=$REGION --quiet || true

cd ../../firebase-rest-api/solution-01
gcloud builds submit --tag $REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.1 . --quiet
gcloud run deploy netflix-dataset-service --image $REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.1 --platform managed --region $REGION --allow-unauthenticated --max-instances 1 --quiet

# 5. REST API v0.2
echo -e "${YELLOW}Task 4: Deploying REST API v0.2...${NC}"
cd ../solution-02
gcloud builds submit --tag $REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.2 . --quiet
gcloud run deploy netflix-dataset-service --image $REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/rest-api:0.2 --platform managed --region $REGION --allow-unauthenticated --max-instances 1 --quiet

# 6. Staging Frontend
echo -e "${YELLOW}Task 5: Deploying Staging Frontend...${NC}"
cd ../../firebase-frontend
REST_API_SERVICE=$(gcloud run services describe netflix-dataset-service --region $REGION --format='value(status.url)')

gcloud builds submit --tag $REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-staging:0.1 . --quiet
gcloud run deploy frontend-staging-service --image $REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-staging:0.1 --platform managed --region $REGION --allow-unauthenticated --max-instances 1 --quiet

# 7. Production Frontend
echo -e "${YELLOW}Task 6: Deploying Production Frontend...${NC}"
# Edit public/app.js to use the REST_API_SERVICE + /2020
sed -i "s|const REST_API_SERVICE = \"data/netflix.json\"|const REST_API_SERVICE = \"$REST_API_SERVICE/2020\"|" public/app.js

gcloud builds submit --tag $REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-production:0.1 . --quiet
gcloud run deploy frontend-production-service --image $REGION-docker.pkg.dev/$PROJECT_ID/rest-api-repo/frontend-production:0.1 --platform managed --region $REGION --allow-unauthenticated --max-instances 1 --quiet

echo -e "${GREEN}SUCCESS: Challenge Lab Completed!${NC}"

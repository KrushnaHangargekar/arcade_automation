#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Starting Automation for GSP642...${NC}"

# 1. Project ID
export PROJECT_ID=$(gcloud config get-value project)
echo -e "${GREEN}Project ID: $PROJECT_ID${NC}"

# 2. APIs
echo -e "${YELLOW}Enabling APIs...${NC}"
gcloud services enable cloudaicompanion.googleapis.com --quiet

# 3. Firestore
echo -e "${YELLOW}Checking Firestore...${NC}"
if gcloud firestore databases list --format="value(name)" | grep -q "default"; then
    echo -e "${GREEN}Firestore already exists.${NC}"
else
    gcloud firestore databases create --location=europe-west4 --type=firestore-native --quiet
fi

# 4. Dependencies
echo -e "${YELLOW}Installing dependencies in lab01...${NC}"
cd lab01
npm install --quiet

# 5. Run Tasks
echo -e "${YELLOW}Generating data...${NC}"
node createTestData.js 1000

echo -e "${YELLOW}Importing data to Firestore...${NC}"
node importTestData.js customers_1000.csv

echo -e "${GREEN}SUCCESS: All tasks completed!${NC}"

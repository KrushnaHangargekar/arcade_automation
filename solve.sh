#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Starting Automation for: Import Data to a Firestore Database...${NC}"

export PROJECT_ID=$(gcloud config get-value project)
echo -e "${GREEN}Project ID: $PROJECT_ID${NC}"

echo -e "${YELLOW}Enabling Cloud AI Companion API...${NC}"
gcloud services enable cloudaicompanion.googleapis.com --quiet

echo -e "${YELLOW}Setting up Firestore in europe-west4...${NC}"
if gcloud firestore databases list --format="value(name)" | grep -q "default"; then
    echo -e "${GREEN}Firestore database already exists.${NC}"
else
    gcloud firestore databases create --location=europe-west4 --type=firestore-native --quiet
fi

# We are already in the directory if running from setup, but for standalone:
# git clone https://github.com/rosera/pet-theory
# cd pet-theory/lab01

echo -e "${YELLOW}Running Data Generation...${NC}"
node createTestData.js 1000

echo -e "${YELLOW}Running Firestore Import...${NC}"
node importTestData.js customers_1000.csv

echo -e "${GREEN}=======================================${NC}"

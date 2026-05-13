# PowerShell Automation for GSP642
Write-Host "Starting Automation for: Import Data to a Firestore Database..." -ForegroundColor Yellow

# 1. Project ID setup
$PROJECT_ID = gcloud config get-value project
Write-Host "Project ID: $PROJECT_ID" -ForegroundColor Green

# 2. API Enable
Write-Host "Enabling Cloud AI Companion API..." -ForegroundColor Yellow
gcloud services enable cloudaicompanion.googleapis.com --quiet

# 3. Firestore Setup
Write-Host "Setting up Firestore in europe-west4..." -ForegroundColor Yellow
$databases = gcloud firestore databases list --format="value(name)"
if ($databases -match "default") {
    Write-Host "Firestore database already exists." -ForegroundColor Green
} else {
    gcloud firestore databases create --location=europe-west4 --type=firestore-native --quiet
}

# 4. Data Generation
Write-Host "Running Data Generation..." -ForegroundColor Yellow
node createTestData.js 1000

# 5. Firestore Import
Write-Host "Running Firestore Import..." -ForegroundColor Yellow
node importTestData.js customers_1000.csv

Write-Host "=======================================" -ForegroundColor Green

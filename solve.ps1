# PowerShell Automation for GSP642
Write-Host "Starting Automation for GSP642..." -ForegroundColor Yellow

$PROJECT_ID = gcloud config get-value project
Write-Host "Project ID: $PROJECT_ID" -ForegroundColor Green

Write-Host "Enabling APIs..." -ForegroundColor Yellow
gcloud services enable cloudaicompanion.googleapis.com --quiet

Write-Host "Checking Firestore..." -ForegroundColor Yellow
$databases = gcloud firestore databases list --format="value(name)"
if ($databases -match "default") {
    Write-Host "Firestore already exists." -ForegroundColor Green
} else {
    gcloud firestore databases create --location=nam5 --type=firestore-native --quiet
}

Write-Host "Installing dependencies in lab01..." -ForegroundColor Yellow
Set-Location lab01
npm install --quiet

Write-Host "Generating data..." -ForegroundColor Yellow
node createTestData.js 1000

Write-Host "Importing data to Firestore..." -ForegroundColor Yellow
node importTestData.js customers_1000.csv

Write-Host "SUCCESS: All tasks completed!" -ForegroundColor Green

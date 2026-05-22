Overview
This folder contains scripts and Cloud Build config templates to run the GitOps lab in Google Cloud Shell.

Usage
1. Upload the contents of this folder to Cloud Shell (or clone this repo into Cloud Shell).
2. In Cloud Shell, run:

```bash
# Set these before running the main script
export GITHUB_USERNAME=your-github-username
export USER_EMAIL=your-email@example.com

# Make script executable and run
chmod +x setup_lab.sh
./setup_lab.sh
```

What the script does
- Sets project variables and enables required APIs
- Creates Artifact Registry repository
- Creates a GKE cluster
- Creates two GitHub repositories (uses `gh`) and initializes them with sample app and env files
- Prepares SSH key and uploads it to Secret Manager (prints instructions to add deploy key)
- Pushes branches and templates to GitHub

Replace placeholders `GITHUB_USERNAME` and `USER_EMAIL` before running.

Files
- `setup_lab.sh`: main script to run in Cloud Shell
- `cloudbuild-app.yaml`: CI pipeline for the app repository
- `cloudbuild-env.yaml`: CD pipeline for the env repository
- `kubernetes.yaml.tpl`: Kubernetes manifest template

Important
- You must run the script in Google Cloud Shell while logged into the provided lab account.
- The script will prompt for installing GitHub CLI auth if necessary.
- It cannot automatically press web-browser auth prompts; follow CLI instructions.

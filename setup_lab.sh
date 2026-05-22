#!/bin/bash
set -euo pipefail

# This script is intended to be run in Google Cloud Shell.
# Before running, export GITHUB_USERNAME and USER_EMAIL.

if [[ -z "${GITHUB_USERNAME:-}" || -z "${USER_EMAIL:-}" || -z "${GH_TOKEN:-}" ]]; then
  echo "Set GITHUB_USERNAME, USER_EMAIL, and GH_TOKEN before running."
  exit 1
fi

export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')

if [[ -z "${REGION:-}" ]]; then
  ZONE=$(gcloud config get-value compute/zone 2>/dev/null || true)
  if [[ -n "$ZONE" ]]; then
    export REGION=${ZONE%-*}
  else
    export REGION="us-central1"
  fi
fi
gcloud config set compute/region $REGION

echo "Enabling APIs..."
gcloud services enable container.googleapis.com \
    cloudbuild.googleapis.com \
    secretmanager.googleapis.com \
    containeranalysis.googleapis.com

echo "Creating Artifact Registry repository..."
gcloud artifacts repositories create my-repository \
  --repository-format=docker \
  --location=$REGION || true

echo "Creating GKE cluster..."
gcloud container clusters create hello-cloudbuild --num-nodes 1 --region $REGION || true

# Setup GitHub CLI and git
if ! command -v gh >/dev/null 2>&1; then
  echo "gh not found. Install it or run the commands manually."
  exit 1
fi

echo "Creating GitHub repos (private)..."
gh repo create hello-cloudbuild-app --private --confirm || true
gh repo create hello-cloudbuild-env --private --confirm || true

# Create app repo content
mkdir -p ~/hello-cloudbuild-app
cat > ~/hello-cloudbuild-app/app.py <<'PY'
from flask import Flask
app = Flask('hello-cloudbuild')
@app.route('/')
def hello():
  return "Hello World!\n"
if __name__ == '__main__':
  app.run(host = '0.0.0.0', port = 8080)
PY

cat > ~/hello-cloudbuild-app/Dockerfile <<'DF'
FROM python:3.7-slim
RUN pip install flask
WORKDIR /app
COPY app.py /app/app.py
ENTRYPOINT ["python"]
CMD ["/app/app.py"]
DF

cat > ~/hello-cloudbuild-app/test_app.py <<'TT'
import unittest
import app

class TestApp(unittest.TestCase):
    def test_hello(self):
        self.assertEqual(app.hello(), "Hello World!\n")

if __name__ == '__main__':
    unittest.main()
TT

# Cloud Build CI config
cat > ~/hello-cloudbuild-app/cloudbuild.yaml <<'CB'
steps:
- name: 'python:3.7-slim'
  id: Test
  entrypoint: /bin/sh
  args:
  - -c
  - 'pip install flask && python test_app.py -v'

- name: 'gcr.io/cloud-builders/docker'
  id: Build
  args:
  - 'build'
  - '-t'
  - 'us-east4-docker.pkg.dev/$PROJECT_ID/my-repository/hello-cloudbuild:$SHORT_SHA'
  - '.'

- name: 'gcr.io/cloud-builders/docker'
  id: Push
  args:
  - 'push'
  - 'us-east4-docker.pkg.dev/$PROJECT_ID/my-repository/hello-cloudbuild:$SHORT_SHA'

# SSH steps and trigger CD will be added separate in the env repo examples
CB

# Initialize git and push app repo
cd ~/hello-cloudbuild-app
git init
git config user.name "$GITHUB_USERNAME"
git config user.email "$USER_EMAIL"
git add .
git commit -m "initial commit"
# Add GitHub remote
git remote add origin https://${GITHUB_USERNAME}:${GH_TOKEN}@github.com/${GITHUB_USERNAME}/hello-cloudbuild-app.git
git branch -M master
git push -u origin master

# Prepare env repo
mkdir -p ~/hello-cloudbuild-env
cat > ~/hello-cloudbuild-env/kubernetes.yaml.tpl <<'K8'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-cloudbuild
spec:
  selector:
    matchLabels:
      app: hello-cloudbuild
  replicas: 1
  template:
    metadata:
      labels:
        app: hello-cloudbuild
    spec:
      containers:
      - name: hello-cloudbuild
        image: us-east4-docker.pkg.dev/GOOGLE_CLOUD_PROJECT/my-repository/hello-cloudbuild:COMMIT_SHA
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: hello-cloudbuild
spec:
  type: LoadBalancer
  selector:
    app: hello-cloudbuild
  ports:
  - port: 80
    targetPort: 8080
K8

cat > ~/hello-cloudbuild-env/cloudbuild.yaml <<'ENV'
steps:
- name: 'gcr.io/cloud-builders/kubectl'
  id: Deploy
  args:
  - 'apply'
  - '-f'
  - 'kubernetes.yaml'
  env:
  - 'CLOUDSDK_COMPUTE_REGION=us-east4'
  - 'CLOUDSDK_CONTAINER_CLUSTER=hello-cloudbuild'

- name: 'gcr.io/cloud-builders/git'
  secretEnv: ['SSH_KEY']
  entrypoint: 'bash'
  args:
  - -c
  - |
    echo "$$SSH_KEY" >> /root/.ssh/id_rsa
    chmod 400 /root/.ssh/id_rsa
    cp known_hosts.github /root/.ssh/known_hosts
  volumes:
  - name: 'ssh'
    path: /root/.ssh

- name: 'gcr.io/cloud-builders/git'
  args:
  - clone
  - --recurse-submodules
  - git@github.com:${GITHUB_USERNAME}/hello-cloudbuild-env.git
  volumes:
  - name: ssh
    path: /root/.ssh

- name: 'gcr.io/cloud-builders/gcloud'
  id: Copy to production branch
  entrypoint: /bin/sh
  args:
  - '-c'
  - |
    set -x && \
    cd hello-cloudbuild-env && \
    git config user.email $(gcloud auth list --filter=status:ACTIVE --format='value(account)')
    sed "s/GOOGLE_CLOUD_PROJECT/${PROJECT_ID}/g" kubernetes.yaml.tpl | \
    git fetch origin production && \
    git checkout production && \
    git checkout $COMMIT_SHA kubernetes.yaml && \
    git commit -m "Manifest from commit $COMMIT_SHA" && \
    git push origin production
  volumes:
  - name: ssh
    path: /root/.ssh

availableSecrets:
  secretManager:
  - versionName: projects/${PROJECT_NUMBER}/secrets/ssh_key_secret/versions/1
    env: 'SSH_KEY'

options:
  logging: CLOUD_LOGGING_ONLY
ENV

# Initialize env git and push branches
cd ~/hello-cloudbuild-env
git init
git config user.name "$GITHUB_USERNAME"
git config user.email "$USER_EMAIL"
cp kubernetes.yaml.tpl kubernetes.yaml
git add .
git commit -m "initial commit"
# Push to GitHub
git remote add origin https://${GITHUB_USERNAME}:${GH_TOKEN}@github.com/${GITHUB_USERNAME}/hello-cloudbuild-env.git
git branch -M master
git push -u origin master

git checkout -b production
git push origin production

git checkout -b candidate
git push origin candidate

# Generate SSH key for Cloud Build to use
mkdir -p ~/workingdir
cd ~/workingdir
ssh-keygen -t rsa -b 4096 -N '' -f id_github -C "$USER_EMAIL"

echo "Public key (add this as a Deploy Key with write access to hello-cloudbuild-env):"
cat id_github.pub

echo "Uploaded private key to Secret Manager (you must run the following manually to upload):"
echo "gcloud secrets create ssh_key_secret --data-file=id_github --replication-policy="automatic" || true"

echo "Grant Cloud Build service account access to Secret Manager:"
echo "gcloud projects add-iam-policy-binding ${PROJECT_NUMBER} --member=serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com --role=roles/secretmanager.secretAccessor"

cat > ~/hello-cloudbuild-app/known_hosts.github <<'KH'
$(ssh-keyscan -t rsa github.com)
KH
chmod +x ~/hello-cloudbuild-app/known_hosts.github

# Push known_hosts
cd ~/hello-cloudbuild-app
git add known_hosts.github
 git commit -m "Add known_hosts" || true
 git push origin master || true

echo "Setup script completed. Follow README.md for next manual steps (add deploy key, upload secret)."

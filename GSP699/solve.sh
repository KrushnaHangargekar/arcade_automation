#!/bin/bash
# ============================================================
#  GSP699 – Migrating a Monolithic Website to Microservices
#           on Google Kubernetes Engine
#
#  Usage:
#    bash solve.sh [start_task]
#
#  Examples:
#    bash solve.sh        → run all tasks from task 1
#    bash solve.sh 4      → resume from task 4
# ============================================================
set -euo pipefail

START_TASK=${1:-1}

# ── Colours ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}[✅]${RESET} $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[⚠️]${RESET} $*"; }
error()   { echo -e "${RED}${BOLD}[❌]${RESET} $*"; exit 1; }
banner()  { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}${CYAN}  $*${RESET}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════${RESET}"; }

# ── Project config ───────────────────────────────────────────
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
[ -z "$PROJECT_ID" ] && error "No active GCP project. Run: gcloud config set project PROJECT_ID"
info "Project: $PROJECT_ID"

ZONE="${ZONE:-us-east4-c}"
REGION="${REGION:-us-east4}"
CLUSTER_NAME="fancy-cluster"
NUM_NODES=3
MACHINE_TYPE="e2-standard-4"

info "Zone  : $ZONE"
info "Region: $REGION"

gcloud config set compute/zone "$ZONE" --quiet
gcloud config set compute/region "$REGION" --quiet

# ── Helper: wait for external IP ─────────────────────────────
wait_for_ip() {
  local svc=$1
  local ip=""
  info "Waiting for external IP of service '$svc'..."
  for i in $(seq 1 30); do
    ip=$(kubectl get service "$svc" \
         --output=jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    if [ -n "$ip" ]; then
      echo "$ip"
      return 0
    fi
    printf "  attempt %d/30 – still pending...\n" "$i"
    sleep 10
  done
  error "Timed out waiting for external IP of service '$svc'"
}

# ════════════════════════════════════════════════════════════
#  TASK 1 – Clone the source repository
# ════════════════════════════════════════════════════════════
if [ "$START_TASK" -le 1 ]; then
  banner "Task 1: Clone Source Repository"

  info "Enabling Container API..."
  gcloud services enable container.googleapis.com --quiet

  cd ~
  if [ ! -d "monolith-to-microservices" ]; then
    info "Cloning monolith-to-microservices repo..."
    git clone https://github.com/googlecodelabs/monolith-to-microservices.git
  else
    warn "Repo already cloned – skipping clone."
  fi

  cd ~/monolith-to-microservices
  info "Running setup.sh (installs NodeJS deps)..."
  ./setup.sh
  success "Task 1 complete – source cloned & dependencies installed."
fi

# ════════════════════════════════════════════════════════════
#  TASK 2 – Create a GKE cluster
# ════════════════════════════════════════════════════════════
if [ "$START_TASK" -le 2 ]; then
  banner "Task 2: Create GKE Cluster"

  # Idempotent – skip if cluster already exists
  if gcloud container clusters describe "$CLUSTER_NAME" --zone "$ZONE" \
       --quiet 2>/dev/null; then
    warn "Cluster '$CLUSTER_NAME' already exists – skipping creation."
  else
    info "Creating GKE cluster '$CLUSTER_NAME' with $NUM_NODES nodes ($MACHINE_TYPE)..."
    gcloud container clusters create "$CLUSTER_NAME" \
      --num-nodes "$NUM_NODES" \
      --machine-type "$MACHINE_TYPE" \
      --zone "$ZONE" \
      --quiet
  fi

  info "Fetching cluster credentials..."
  gcloud container clusters get-credentials "$CLUSTER_NAME" \
    --zone "$ZONE" --quiet

  info "Verifying worker nodes:"
  gcloud compute instances list --filter="name~gke-${CLUSTER_NAME}"
  success "Task 2 complete – GKE cluster ready."
fi

# ════════════════════════════════════════════════════════════
#  TASK 3 – Deploy the existing Monolith
# ════════════════════════════════════════════════════════════
if [ "$START_TASK" -le 3 ]; then
  banner "Task 3: Deploy Existing Monolith"

  cd ~/monolith-to-microservices

  # Ensure credentials are fresh
  gcloud container clusters get-credentials "$CLUSTER_NAME" \
    --zone "$ZONE" --quiet

  info "Running deploy-monolith.sh..."
  ./deploy-monolith.sh

  MONOLITH_IP=$(wait_for_ip monolith)
  success "Task 3 complete – Monolith accessible at: http://$MONOLITH_IP"
fi

# ════════════════════════════════════════════════════════════
#  TASK 4 – Migrate Orders to a microservice
# ════════════════════════════════════════════════════════════
if [ "$START_TASK" -le 4 ]; then
  banner "Task 4: Migrate Orders to Microservice"

  gcloud container clusters get-credentials "$CLUSTER_NAME" \
    --zone "$ZONE" --quiet

  # 4a – Build Orders Docker image with Cloud Build
  info "Building Orders Docker image..."
  cd ~/monolith-to-microservices/microservices/src/orders
  gcloud builds submit \
    --tag "gcr.io/${GOOGLE_CLOUD_PROJECT}/orders:1.0.0" \
    . --quiet

  # 4b – Deploy to GKE
  info "Creating Orders deployment..."
  if kubectl get deployment orders &>/dev/null; then
    warn "Deployment 'orders' already exists – updating image..."
    kubectl set image deployment/orders orders="gcr.io/${GOOGLE_CLOUD_PROJECT}/orders:1.0.0"
  else
    kubectl create deployment orders \
      --image="gcr.io/${GOOGLE_CLOUD_PROJECT}/orders:1.0.0"
  fi

  # 4c – Expose via LoadBalancer
  info "Exposing Orders service..."
  if ! kubectl get service orders &>/dev/null; then
    kubectl expose deployment orders \
      --type=LoadBalancer \
      --port 80 \
      --target-port 8081
  else
    warn "Service 'orders' already exists – skipping expose."
  fi

  # 4d – Get external IP
  ORDERS_IP=$(wait_for_ip orders)
  info "Orders microservice IP: $ORDERS_IP"

  # 4e – Reconfigure monolith to point at Orders microservice
  info "Patching monolith .env.monolith with Orders IP..."
  cd ~/monolith-to-microservices/react-app
  # Write the file directly (avoids interactive nano)
  # Preserve PRODUCTS_URL as local for now
  cat > .env.monolith <<EOF
REACT_APP_ORDERS_URL=http://${ORDERS_IP}/api/orders
REACT_APP_PRODUCTS_URL=/service/products
EOF
  info ".env.monolith updated:"
  cat .env.monolith

  # 4f – Rebuild monolith frontend
  info "Rebuilding monolith frontend..."
  npm run build:monolith

  # 4g – Build & deploy monolith v2
  info "Building monolith Docker image v2.0.0..."
  cd ~/monolith-to-microservices/monolith
  gcloud builds submit \
    --tag "gcr.io/${GOOGLE_CLOUD_PROJECT}/monolith:2.0.0" \
    . --quiet

  info "Updating monolith deployment to v2.0.0..."
  kubectl set image deployment/monolith \
    monolith="gcr.io/${GOOGLE_CLOUD_PROJECT}/monolith:2.0.0"

  # Save IP for later tasks
  echo "$ORDERS_IP" > /tmp/gsp699_orders_ip.txt
  success "Task 4 complete – Orders microservice live at http://$ORDERS_IP"
fi

# ════════════════════════════════════════════════════════════
#  TASK 5 – Migrate Products to a microservice
# ════════════════════════════════════════════════════════════
if [ "$START_TASK" -le 5 ]; then
  banner "Task 5: Migrate Products to Microservice"

  gcloud container clusters get-credentials "$CLUSTER_NAME" \
    --zone "$ZONE" --quiet

  # Restore Orders IP from previous task or re-derive
  if [ -f /tmp/gsp699_orders_ip.txt ]; then
    ORDERS_IP=$(cat /tmp/gsp699_orders_ip.txt)
  else
    ORDERS_IP=$(wait_for_ip orders)
  fi
  info "Orders IP: $ORDERS_IP"

  # 5a – Build Products Docker image with Cloud Build
  info "Building Products Docker image..."
  cd ~/monolith-to-microservices/microservices/src/products
  gcloud builds submit \
    --tag "gcr.io/${GOOGLE_CLOUD_PROJECT}/products:1.0.0" \
    . --quiet

  # 5b – Deploy to GKE
  info "Creating Products deployment..."
  if kubectl get deployment products &>/dev/null; then
    warn "Deployment 'products' already exists – updating image..."
    kubectl set image deployment/products products="gcr.io/${GOOGLE_CLOUD_PROJECT}/products:1.0.0"
  else
    kubectl create deployment products \
      --image="gcr.io/${GOOGLE_CLOUD_PROJECT}/products:1.0.0"
  fi

  # 5c – Expose via LoadBalancer
  info "Exposing Products service..."
  if ! kubectl get service products &>/dev/null; then
    kubectl expose deployment products \
      --type=LoadBalancer \
      --port 80 \
      --target-port 8082
  else
    warn "Service 'products' already exists – skipping expose."
  fi

  # 5d – Get external IP
  PRODUCTS_IP=$(wait_for_ip products)
  info "Products microservice IP: $PRODUCTS_IP"

  # 5e – Reconfigure monolith to point at both microservices
  info "Patching monolith .env.monolith with Products IP..."
  cd ~/monolith-to-microservices/react-app
  cat > .env.monolith <<EOF
REACT_APP_ORDERS_URL=http://${ORDERS_IP}/api/orders
REACT_APP_PRODUCTS_URL=http://${PRODUCTS_IP}/api/products
EOF
  info ".env.monolith updated:"
  cat .env.monolith

  # 5f – Rebuild monolith frontend
  info "Rebuilding monolith frontend..."
  npm run build:monolith

  # 5g – Build & deploy monolith v3
  info "Building monolith Docker image v3.0.0..."
  cd ~/monolith-to-microservices/monolith
  gcloud builds submit \
    --tag "gcr.io/${GOOGLE_CLOUD_PROJECT}/monolith:3.0.0" \
    . --quiet

  info "Updating monolith deployment to v3.0.0..."
  kubectl set image deployment/monolith \
    monolith="gcr.io/${GOOGLE_CLOUD_PROJECT}/monolith:3.0.0"

  # Save IP for later tasks
  echo "$PRODUCTS_IP" > /tmp/gsp699_products_ip.txt
  success "Task 5 complete – Products microservice live at http://$PRODUCTS_IP"
fi

# ════════════════════════════════════════════════════════════
#  TASK 6 – Migrate Frontend to a microservice & delete monolith
# ════════════════════════════════════════════════════════════
if [ "$START_TASK" -le 6 ]; then
  banner "Task 6: Migrate Frontend & Decommission Monolith"

  gcloud container clusters get-credentials "$CLUSTER_NAME" \
    --zone "$ZONE" --quiet

  # Restore IPs from previous tasks or re-derive
  if [ -f /tmp/gsp699_orders_ip.txt ]; then
    ORDERS_IP=$(cat /tmp/gsp699_orders_ip.txt)
  else
    ORDERS_IP=$(wait_for_ip orders)
  fi
  if [ -f /tmp/gsp699_products_ip.txt ]; then
    PRODUCTS_IP=$(cat /tmp/gsp699_products_ip.txt)
  else
    PRODUCTS_IP=$(wait_for_ip products)
  fi
  info "Orders IP  : $ORDERS_IP"
  info "Products IP: $PRODUCTS_IP"

  # 6a – Copy microservices config and build React app
  info "Copying microservices config to frontend..."
  cd ~/monolith-to-microservices/react-app
  cp .env.monolith .env
  npm run build

  # 6b – Build Frontend Docker image with Cloud Build
  info "Building Frontend Docker image..."
  cd ~/monolith-to-microservices/microservices/src/frontend
  gcloud builds submit \
    --tag "gcr.io/${GOOGLE_CLOUD_PROJECT}/frontend:1.0.0" \
    . --quiet

  # 6c – Deploy to GKE
  info "Creating Frontend deployment..."
  if kubectl get deployment frontend &>/dev/null; then
    warn "Deployment 'frontend' already exists – updating image..."
    kubectl set image deployment/frontend frontend="gcr.io/${GOOGLE_CLOUD_PROJECT}/frontend:1.0.0"
  else
    kubectl create deployment frontend \
      --image="gcr.io/${GOOGLE_CLOUD_PROJECT}/frontend:1.0.0"
  fi

  # 6d – Expose via LoadBalancer
  info "Exposing Frontend service..."
  if ! kubectl get service frontend &>/dev/null; then
    kubectl expose deployment frontend \
      --type=LoadBalancer \
      --port 80 \
      --target-port 8080
  else
    warn "Service 'frontend' already exists – skipping expose."
  fi

  # 6e – Delete the monolith
  info "Deleting monolith deployment and service..."
  kubectl delete deployment monolith --ignore-not-found
  kubectl delete service monolith --ignore-not-found

  # 6f – Get frontend external IP
  FRONTEND_IP=$(wait_for_ip frontend)

  success "Task 6 complete – Frontend microservice live at: http://$FRONTEND_IP"
  info "All microservices running. Monolith decommissioned."
fi

# ════════════════════════════════════════════════════════════
#  FINAL SUMMARY
# ════════════════════════════════════════════════════════════
banner "🎉  ALL TASKS COMPLETE – GSP699"
echo ""
gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$ZONE" --quiet 2>/dev/null || true
echo -e "${BOLD}Service Summary:${RESET}"
kubectl get services 2>/dev/null || true
echo ""
FRONTEND_IP=$(kubectl get service frontend \
  --output=jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
echo -e "${GREEN}${BOLD}  🌐 Full App  →  http://${FRONTEND_IP}${RESET}"
echo -e "${GREEN}${BOLD}  🛒 Orders    →  http://$(cat /tmp/gsp699_orders_ip.txt 2>/dev/null || echo pending)/api/orders${RESET}"
echo -e "${GREEN}${BOLD}  📦 Products  →  http://$(cat /tmp/gsp699_products_ip.txt 2>/dev/null || echo pending)/api/products${RESET}"
echo ""

#!/bin/bash

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================
CLUSTER_NAME="p3-cluster"
ARGOCD_NS="argocd"
DEV_NS="dev"
APP_SVC_NAME="kzegani-playground"

# Use absolute paths! Assuming /vagrant based on your earlier scripts.
INGRESS_MANIFEST="/vagrant/confs/ingress.yaml"
ARGO_APP_MANIFEST="/vagrant/confs/application.yaml"
APP_DEPLOYMENT_MANIFEST="/vagrant/confs/manifests/deployment.yaml"

PASSWORD_FILE="/root/argocd-admin-password.txt"

# ==============================================================================
# LOGGING UI DEFINITIONS
# ==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

log_info()    { echo -e "${CYAN}[ARGO CD INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[ARGO CD SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[ARGO CD WARN]${NC} $1"; }
log_error()   { echo -e "${RED}${BOLD}[ARGO CD ERROR]${NC} $1" >&2; }

print_banner() {
  echo -e "\n${CYAN}################################################################################${NC}"
  echo -e "${CYAN}# $1${NC}"
  echo -e "${CYAN}################################################################################${NC}\n"
}

# ==============================================================================
# PREREQUISITES
# ==============================================================================
print_banner "System Prerequisites"

if ! command -v kubectl &> /dev/null; then
  log_info "kubectl not found. Fetching stable release version..."
  KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
  
  if [ -z "${KUBECTL_VERSION}" ]; then
    log_error "Failed to fetch kubectl version. Check network."
    exit 1
  fi

  log_info "Downloading kubectl ${KUBECTL_VERSION}..."
  curl -L -s -o ./kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  chmod +x ./kubectl
  mv ./kubectl /usr/local/bin/kubectl
  log_success "kubectl installed successfully."
else
  log_info "kubectl already installed. Skipping..."
fi

# ==============================================================================
# CLUSTER PROVISIONING
# ==============================================================================
print_banner "k3d Cluster Setup"

log_info "Checking for existing cluster '${CLUSTER_NAME}'..."
if k3d cluster list "${CLUSTER_NAME}" &> /dev/null; then
  log_warn "Cluster '${CLUSTER_NAME}' already exists. Skipping creation."
else
  log_info "Provisioning new k3d cluster '${CLUSTER_NAME}'..."
  k3d cluster create "${CLUSTER_NAME}" \
    -p "8443:443@loadbalancer" \
    -p "8888:80@loadbalancer"
  log_success "Cluster '${CLUSTER_NAME}' created."
fi

# ==============================================================================
# NAMESPACE & ARGO CD INSTALLATION
# ==============================================================================
print_banner "Installing Argo CD"

log_info "Ensuring namespaces (${ARGOCD_NS}, ${DEV_NS}) exist..."
kubectl create namespace "${ARGOCD_NS}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create namespace "${DEV_NS}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

log_info "Applying Argo CD manifests from stable branch..."
kubectl apply --server-side --force-conflicts -n "${ARGOCD_NS}" -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

log_info "Waiting for Argo CD Server deployment to roll out..."
kubectl rollout status deployment/argocd-server -n "${ARGOCD_NS}" --timeout=300s

log_info "Patching ConfigMap to disable internal TLS..."
kubectl patch configmap argocd-cmd-params-cm -n "${ARGOCD_NS}" --type merge -p '{"data":{"server.insecure":"true"}}'

log_info "Restarting Argo CD server to apply insecure mode..."
kubectl rollout restart deployment argocd-server -n "${ARGOCD_NS}"
kubectl rollout status deployment argocd-server -n "${ARGOCD_NS}" --timeout=300s

# ==============================================================================
# CREDENTIAL RETRIEVAL
# ==============================================================================
print_banner "Retrieving Credentials"

log_info "Retrieving initial admin secret..."
TIMEOUT=60
SLEEP_INTERVAL=2

while ! kubectl -n "${ARGOCD_NS}" get secret argocd-initial-admin-secret &>/dev/null; do
  if [ "$TIMEOUT" -le 0 ]; then
    log_error "Timeout waiting for Argo CD admin secret."
    exit 1
  fi
  log_warn "Secret not yet generated, waiting... [remaining ${TIMEOUT}s]"
  sleep "${SLEEP_INTERVAL}"
  ((TIMEOUT-=SLEEP_INTERVAL))
done

ARGOCD_PASS=$(kubectl -n "${ARGOCD_NS}" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo "${ARGOCD_PASS}" > "${PASSWORD_FILE}"
log_success "Admin password saved to ${PASSWORD_FILE}."

# ==============================================================================
# APPLICATION DEPLOYMENT
# ==============================================================================
print_banner "Deploying Application & Ingress"

log_info "Applying ingress routing..."
if [ -f "${INGRESS_MANIFEST}" ]; then
  kubectl apply -f "${INGRESS_MANIFEST}"
  log_success "Ingress applied."
else
  log_error "Ingress manifest not found at ${INGRESS_MANIFEST}. Skipping."
fi

log_info "Applying application manifests..."
if [ -f "${APP_DEPLOYMENT_MANIFEST}" ] && [ -f "${ARGO_APP_MANIFEST}" ]; then
  kubectl apply -f "${APP_DEPLOYMENT_MANIFEST}"
  kubectl apply -f "${ARGO_APP_MANIFEST}"
  log_success "Application manifests applied."
else
  log_error "One or more application manifests not found. Check your paths."
  exit 1
fi

log_info "Waiting for Argo CD to sync and create the '${APP_SVC_NAME}' service..."
SVC_TIMEOUT=120
while ! kubectl get svc "${APP_SVC_NAME}" -n "${DEV_NS}" &>/dev/null; do
  if [ "$SVC_TIMEOUT" -le 0 ]; then
    log_error "Timeout waiting for service '${APP_SVC_NAME}' to be synced by Argo CD."
    exit 1
  fi
  log_warn "Service not found yet. Waiting for Argo CD sync... [remaining ${SVC_TIMEOUT}s]"
  sleep 2
  ((SVC_TIMEOUT-=2))
done

# ==============================================================================
# SUMMARY
# ==============================================================================
print_banner "Deployment Summary"
log_success "Argo CD URL: https://argocd.com:8443"
log_success "Argo CD UI Username: admin"
log_success "Argo CD UI Password: ${ARGOCD_PASS}"
log_success "Application LoadBalancer configured on port 8888"

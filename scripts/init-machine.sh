#!/bin/bash

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================
TARGET_USER="vagrant"
DOCKER_KEYRING="/etc/apt/keyrings/docker.asc"
DOCKER_SOURCE_LIST="/etc/apt/sources.list.d/docker.sources"

# ==============================================================================
# LOGGING UI DEFINITIONS
# ==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

log_info()    { echo -e "${CYAN}[INIT INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[INIT SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[INIT WARN]${NC} $1"; }
log_error()   { echo -e "${RED}${BOLD}[INIT ERROR]${NC} $1" >&2; }

print_banner() {
  echo -e "\n${CYAN}################################################################################${NC}"
  echo -e "${CYAN}# $1${NC}"
  echo -e "${CYAN}################################################################################${NC}\n"
}

# ==============================================================================
# BASE SYSTEM PREPARATION
# ==============================================================================
print_banner "System Initialization & Cleanup"

export DEBIAN_FRONTEND=noninteractive

log_info "Updating base package lists and installing prerequisites..."
apt-get update -qq
apt-get install -y curl net-tools ca-certificates

log_info "Purging conflicting legacy Docker packages..."
# Using || true ensures the script doesn't crash if the packages don't exist
apt-get remove -y docker.io docker-doc docker-compose podman-docker containerd runc 2>/dev/null || true

# ==============================================================================
# DOCKER INSTALLATION
# ==============================================================================
print_banner "Provisioning Docker Engine"

log_info "Importing Docker's official GPG key..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o "${DOCKER_KEYRING}"
chmod a+r "${DOCKER_KEYRING}"

log_info "Configuring Docker APT repository..."
# Fetch the codename dynamically and securely write the deb822 source file
OS_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")

cat <<EOF | tee "${DOCKER_SOURCE_LIST}" > /dev/null
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: ${OS_CODENAME}
Components: stable
Signed-By: ${DOCKER_KEYRING}
EOF

log_info "Updating package index with Docker repository..."
apt-get update -qq

log_info "Installing Docker Engine and associated plugins..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# ==============================================================================
# K3D INSTALLATION
# ==============================================================================
print_banner "Installing k3d"

log_info "Pulling and executing k3d installation script..."
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# ==============================================================================
# USER PERMISSIONS
# ==============================================================================
print_banner "Finalizing Permissions"

log_info "Adding user '${TARGET_USER}' to the 'docker' group..."
if id "${TARGET_USER}" &>/dev/null; then
  usermod -aG docker "${TARGET_USER}"
  log_success "Permissions applied. '${TARGET_USER}' can now execute docker commands."
else
  log_warn "User '${TARGET_USER}' does not exist. Skipping group assignment."
fi

print_banner "Initialization Complete"
log_success "Machine successfully provisioned with Docker and k3d."
log_info "Note: You may need to log out and log back in (or run 'newgrp docker') for group changes to take full effect."

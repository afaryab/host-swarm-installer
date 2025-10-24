#!/usr/bin/env bash
set -euo pipefail

# =========================
# Module 01: Docker Validation and Installation
# =========================

log() { echo -e "\033[1;32m[+] $*\033[0m"; }
err() { echo -e "\033[1;31m[✗] $*\033[0m"; }
info() { echo -e "\033[1;34m[i] $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }

validate_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker is already installed."
    docker --version
    return 0
  else
    warn "Docker is not installed."
    return 1
  fi
}

install_docker() {
  log "Installing Docker Engine..."
  
  if [[ -e /etc/debian_version ]]; then
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release
    
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Set up the repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") \
      $(. /etc/os-release; echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list
    
    # Install Docker Engine
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io \
                       docker-buildx-plugin docker-compose-plugin jq
    
    # Enable and start Docker service
    systemctl enable --now docker
    
    log "Docker installed successfully."
    docker --version
  else
    err "This installer currently supports Debian/Ubuntu only."
    err "Please install Docker manually from: https://docs.docker.com/engine/install/"
    exit 1
  fi
}

main() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "This module must be run as root (use sudo)."
    exit 1
  fi
  
  echo "========================================"
  echo "Module 01: Docker Installation"
  echo "========================================"
  echo
  
  if validate_docker; then
    info "Docker validation successful."
  else
    info "Docker not found. Installing now..."
    install_docker
  fi
  
  log "Module 01 completed successfully."
}

main "$@"

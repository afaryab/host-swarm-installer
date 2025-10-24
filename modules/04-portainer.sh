#!/usr/bin/env bash
set -euo pipefail

# =========================
# Module 04: Portainer Setup
# =========================

log() { echo -e "\033[1;32m[+] $*\033[0m"; }
err() { echo -e "\033[1;31m[✗] $*\033[0m"; }
info() { echo -e "\033[1;34m[i] $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }

BASE_DIR="/mnt/hosting/infrastructure/portainer"
PROGRESS_FILE="/mnt/hosting/infrastructure/.install_progress.json"

prompt_required() {
  local prompt="$1"; local var
  while true; do
    read -rp "$prompt: " var || true
    if [[ -n "$var" ]]; then
      echo "$var"
      return
    fi
    warn "This field is required. Please provide a value."
  done
}

create_portainer_directories() {
  log "Creating Portainer directory structure..."
  mkdir -p "$BASE_DIR/data"
  log "Directories created at: $BASE_DIR"
}

ask_portainer_installation() {
  echo "========================================"
  echo "Portainer Installation"
  echo "========================================"
  echo
  info "Portainer provides a web-based Docker management interface."
  echo
  
  local install_choice
  while true; do
    read -rp "Do you want to install Portainer? [y/n]: " install_choice
    case "${install_choice,,}" in
      y|yes)
        return 0
        ;;
      n|no)
        info "Skipping Portainer installation."
        return 1
        ;;
      *)
        warn "Please enter 'y' or 'n'."
        ;;
    esac
  done
}

ask_portainer_exposure() {
  echo
  info "How do you want to expose Portainer?"
  echo "  1) Public (with domain via Traefik - HTTPS)"
  echo "  2) Local (expose port 9000 directly)"
  echo
  
  local choice
  while true; do
    read -rp "Enter your choice [1-2]: " choice
    case "$choice" in
      1)
        echo "public"
        return
        ;;
      2)
        echo "local"
        return
        ;;
      *)
        warn "Invalid choice. Please enter 1 or 2."
        ;;
    esac
  done
}

create_portainer_compose_public() {
  local domain="$1"
  
  log "Creating Portainer docker-compose.yml for public access..."
  cat > "$BASE_DIR/docker-compose.yml" <<EOF
version: '3.8'

services:
  portainer:
    image: portainer/portainer-ce:latest
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    volumes:
      - ${PWD}/data:/data
    networks:
      - traefik-net
      - portainer-agent-net
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.portainer.rule=Host(\`${domain}\`)"
        - "traefik.http.routers.portainer.entrypoints=websecure"
        - "traefik.http.routers.portainer.tls.certresolver=letsencrypt"
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"

  agent:
    image: portainer/agent:latest
    environment:
      AGENT_CLUSTER_ADDR: tasks.agent
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks:
      - portainer-agent-net
    deploy:
      mode: global
      placement:
        constraints:
          - node.platform.os == linux

networks:
  traefik-net:
    external: true
  portainer-agent-net:
    driver: overlay
    attachable: true
EOF
  
  log "docker-compose.yml created: $BASE_DIR/docker-compose.yml"
  info "Portainer will be accessible at: https://${domain}"
}

create_portainer_compose_local() {
  log "Creating Portainer docker-compose.yml for local access..."
  cat > "$BASE_DIR/docker-compose.yml" <<'EOF'
version: '3.8'

services:
  portainer:
    image: portainer/portainer-ce:latest
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    ports:
      - "9000:9000"
    volumes:
      - ${PWD}/data:/data
    networks:
      - portainer-agent-net
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager

  agent:
    image: portainer/agent:latest
    environment:
      AGENT_CLUSTER_ADDR: tasks.agent
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks:
      - portainer-agent-net
    deploy:
      mode: global
      placement:
        constraints:
          - node.platform.os == linux

networks:
  portainer-agent-net:
    driver: overlay
    attachable: true
EOF
  
  log "docker-compose.yml created: $BASE_DIR/docker-compose.yml"
  info "Portainer will be accessible at: http://<server-ip>:9000"
}

deploy_portainer() {
  log "Deploying Portainer stack..."
  cd "$BASE_DIR"
  docker stack deploy -c docker-compose.yml portainer
  log "Portainer stack deployed successfully!"
  echo
  info "Waiting for Portainer to start..."
  sleep 5
  docker service ls | grep portainer || true
  echo
  info "First-time setup: Create your admin account by visiting the Portainer URL."
}

save_portainer_choice() {
  local installed="$1"
  mkdir -p "$(dirname "$PROGRESS_FILE")"
  
  if [[ ! -f "$PROGRESS_FILE" ]]; then
    echo '{}' > "$PROGRESS_FILE"
  fi
  
  local tmp=$(mktemp)
  jq --arg installed "$installed" '.portainer_installed = $installed' "$PROGRESS_FILE" > "$tmp" && mv "$tmp" "$PROGRESS_FILE"
}

main() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "This module must be run as root (use sudo)."
    exit 1
  fi
  
  echo "========================================"
  echo "Module 04: Portainer Setup"
  echo "========================================"
  echo
  
  if ! ask_portainer_installation; then
    save_portainer_choice "false"
    log "Module 04 completed (Portainer skipped)."
    exit 0
  fi
  
  create_portainer_directories
  
  local exposure_type
  exposure_type=$(ask_portainer_exposure)
  
  if [[ "$exposure_type" == "public" ]]; then
    echo
    local domain
    domain=$(prompt_required "Enter domain for Portainer (e.g., portainer.example.com)")
    create_portainer_compose_public "$domain"
  else
    create_portainer_compose_local
  fi
  
  deploy_portainer
  save_portainer_choice "true"
  
  log "Module 04 completed successfully."
}

main "$@"

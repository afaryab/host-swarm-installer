#!/usr/bin/env bash
set -euo pipefail

# =========================
# Module 03: Traefik Setup with Cloudflare
# =========================

log() { echo -e "\033[1;32m[+] $*\033[0m"; }
err() { echo -e "\033[1;31m[✗] $*\033[0m"; }
info() { echo -e "\033[1;34m[i] $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }

BASE_DIR="/mnt/hosting/infrastructure/traefik"

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

prompt_default() {
  local prompt="$1"; local default="$2"; local var
  read -rp "$prompt [$default]: " var || true
  echo "${var:-$default}"
}

create_traefik_directories() {
  log "Creating Traefik directory structure..."
  mkdir -p "$BASE_DIR"/{letsencrypt,dynamic,dynamic/certs,logs}
  touch "$BASE_DIR/letsencrypt/acme.json"
  chmod 600 "$BASE_DIR/letsencrypt/acme.json"
  log "Directories created at: $BASE_DIR"
}

create_traefik_network() {
  log "Creating traefik-net overlay network..."
  if docker network inspect traefik-net >/dev/null 2>&1; then
    info "traefik-net network already exists."
  else
    docker network create --driver overlay --attachable traefik-net
    log "traefik-net network created."
  fi
}

collect_traefik_variables() {
  echo "========================================"
  echo "Traefik Configuration"
  echo "========================================"
  echo
  
  info "Please provide the following information:"
  echo
  
  # Email for Let's Encrypt
  ACME_EMAIL=$(prompt_required "Email for Let's Encrypt notifications")
  
  # Cloudflare configuration
  echo
  info "Cloudflare DNS Challenge Configuration"
  warn "You need a Cloudflare API token with DNS edit permissions."
  echo
  
  CF_API_EMAIL=$(prompt_required "Cloudflare account email")
  CF_DNS_API_TOKEN=$(prompt_required "Cloudflare DNS API Token")
  
}

create_traefik_env() {
  log "Creating Traefik environment file..."
  cat > "$BASE_DIR/.env" <<EOF
# Traefik Configuration
ACME_EMAIL=$ACME_EMAIL

# Cloudflare Configuration
CF_API_EMAIL=$CF_API_EMAIL
CF_DNS_API_TOKEN=$CF_DNS_API_TOKEN

EOF
  chmod 600 "$BASE_DIR/.env"
  log "Environment file created: $BASE_DIR/.env"
}

create_traefik_compose() {
  log "Creating Traefik docker-compose.yml..."
  cat > "$BASE_DIR/docker-compose.yml" <<'EOF'
version: '3.8'

services:
  traefik:
    image: traefik:v3.5
    command:
      - --providers.swarm=true
      - --providers.swarm.network=traefik-net
      - --providers.swarm.exposedByDefault=false
      - --providers.file.directory=/dynamic
      - --providers.file.watch=true
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --api.dashboard=true
      - --api.insecure=true
      - --certificatesresolvers.le.acme.email=${ACME_EMAIL}
      - --certificatesresolvers.le.acme.storage=/letsencrypt/acme.json
      - --certificatesresolvers.le.acme.dnschallenge=true
      - --certificatesresolvers.le.acme.dnschallenge.provider=cloudflare
      - --certificatesresolvers.le.acme.dnschallenge.delaybeforecheck=0
      - --certificatesresolvers.le.acme.dnschallenge.resolvers=1.1.1.1:53,8.8.8.8:53
      - --serversTransport.insecureSkipVerify=false
      - --log.level=INFO
      - --accesslog=true
      - --accesslog.filepath=/var/log/traefik/access.log
    
    environment:
      - CF_API_EMAIL=${CF_API_EMAIL}
      - CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN}
    
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"
    
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./letsencrypt:/letsencrypt
      - ./dynamic:/etc/traefik/dynamic
      - ./logs:/var/log/traefik
    
    networks:
      - traefik-net
    
    deploy:
      mode: global
      placement:
        constraints:
          - node.role == manager

networks:
  traefik-net:
    external: true
EOF
  log "docker-compose.yml created: $BASE_DIR/docker-compose.yml"
}

deploy_traefik() {
  log "Deploying Traefik stack..."
  cd "$BASE_DIR"
  docker stack deploy -c docker-compose.yml traefik
  log "Traefik stack deployed successfully!"
  echo
  info "Waiting for Traefik to start..."
  sleep 5
  docker service ls | grep traefik || true
}

main() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "This module must be run as root (use sudo)."
    exit 1
  fi
  
  echo "========================================"
  echo "Module 03: Traefik Setup"
  echo "========================================"
  echo
  
  create_traefik_directories
  create_traefik_network
  collect_traefik_variables
  create_traefik_env
  create_traefik_compose
  deploy_traefik
  
  log "Module 03 completed successfully."
}

main "$@"

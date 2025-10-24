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
  
  # Traefik dashboard domain
  TRAEFIK_DOMAIN=$(prompt_required "Domain for Traefik dashboard (e.g., traefik.example.com)")
  
  # Cloudflare configuration
  echo
  info "Cloudflare DNS Challenge Configuration"
  warn "You need a Cloudflare API token with DNS edit permissions."
  echo
  
  CF_API_EMAIL=$(prompt_required "Cloudflare account email")
  CF_DNS_API_TOKEN=$(prompt_required "Cloudflare DNS API Token")
  
  # Optional: Traefik dashboard credentials
  echo
  info "Traefik Dashboard Authentication (optional)"
  TRAEFIK_USER=$(prompt_default "Dashboard username" "admin")
  TRAEFIK_PASSWORD=$(prompt_required "Dashboard password")
  
  # Generate htpasswd for basic auth
  TRAEFIK_HASHED_PASSWORD=$(openssl passwd -apr1 "$TRAEFIK_PASSWORD")
}

create_traefik_env() {
  log "Creating Traefik environment file..."
  cat > "$BASE_DIR/.env" <<EOF
# Traefik Configuration
ACME_EMAIL=$ACME_EMAIL
TRAEFIK_DOMAIN=$TRAEFIK_DOMAIN

# Cloudflare Configuration
CF_API_EMAIL=$CF_API_EMAIL
CF_DNS_API_TOKEN=$CF_DNS_API_TOKEN

# Dashboard Authentication
TRAEFIK_USER=$TRAEFIK_USER
TRAEFIK_HASHED_PASSWORD=$TRAEFIK_HASHED_PASSWORD
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
    image: traefik:v2.10
    command:
      # API and Dashboard
      - "--api.dashboard=true"
      - "--api.insecure=false"
      
      # Providers
      - "--providers.docker=true"
      - "--providers.docker.swarmMode=true"
      - "--providers.docker.exposedByDefault=false"
      - "--providers.docker.network=traefik-net"
      - "--providers.file.directory=/etc/traefik/dynamic"
      - "--providers.file.watch=true"
      
      # Entrypoints
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
      - "--entrypoints.websecure.address=:443"
      
      # Let's Encrypt with Cloudflare DNS Challenge
      - "--certificatesresolvers.letsencrypt.acme.email=${ACME_EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.letsencrypt.acme.dnschallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.dnschallenge.provider=cloudflare"
      - "--certificatesresolvers.letsencrypt.acme.dnschallenge.resolvers=1.1.1.1:53,8.8.8.8:53"
      
      # Logging
      - "--log.level=INFO"
      - "--accesslog=true"
      - "--accesslog.filepath=/var/log/traefik/access.log"
    
    environment:
      - CF_API_EMAIL=${CF_API_EMAIL}
      - CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN}
    
    ports:
      - "80:80"
      - "443:443"
    
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ${PWD}/letsencrypt:/letsencrypt
      - ${PWD}/dynamic:/etc/traefik/dynamic
      - ${PWD}/logs:/var/log/traefik
    
    networks:
      - traefik-net
    
    deploy:
      mode: global
      placement:
        constraints:
          - node.role == manager
      labels:
        # Dashboard
        - "traefik.enable=true"
        - "traefik.http.routers.traefik-dashboard.rule=Host(`${TRAEFIK_DOMAIN}`)"
        - "traefik.http.routers.traefik-dashboard.entrypoints=websecure"
        - "traefik.http.routers.traefik-dashboard.tls.certresolver=letsencrypt"
        - "traefik.http.routers.traefik-dashboard.service=api@internal"
        - "traefik.http.routers.traefik-dashboard.middlewares=traefik-auth"
        - "traefik.http.services.traefik-dashboard.loadbalancer.server.port=8080"
        
        # Basic Auth Middleware
        - "traefik.http.middlewares.traefik-auth.basicauth.users=${TRAEFIK_USER}:${TRAEFIK_HASHED_PASSWORD}"

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
  info "Traefik dashboard will be available at: https://$TRAEFIK_DOMAIN"
  info "Username: $TRAEFIK_USER"
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

#!/usr/bin/env bash
set -euo pipefail

# =========================
# Module 06: Identity Provider (Keycloak) Setup
# =========================

log() { echo -e "\033[1;32m[+] $*\033[0m"; }
err() { echo -e "\033[1;31m[✗] $*\033[0m"; }
info() { echo -e "\033[1;34m[i] $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }

BASE_DIR="/mnt/hosting/infrastructure/identity-provider"
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

prompt_default() {
  local prompt="$1"; local default="$2"; local var
  read -rp "$prompt [$default]: " var || true
  echo "${var:-$default}"
}

check_server_manager_installed() {
  if [[ ! -f "$PROGRESS_FILE" ]]; then
    return 1
  fi
  
  local installed
  installed=$(jq -r '.server_manager_installed // false' "$PROGRESS_FILE")
  
  if [[ "$installed" == "true" ]]; then
    return 0
  else
    return 1
  fi
}

create_directories() {
  log "Creating Identity Provider directory structure..."
  mkdir -p "$BASE_DIR"/{data,postgres}
  log "Directories created at: $BASE_DIR"
}

ask_identity_provider_installation() {
  echo "========================================"
  echo "Identity Provider (Keycloak) Installation"
  echo "========================================"
  echo
  
  if ! check_server_manager_installed; then
    warn "Server Manager was not installed. Identity Provider requires Server Manager."
    info "Skipping Identity Provider installation."
    return 1
  fi
  
  info "Keycloak provides authentication and authorization for Server Manager."
  echo
  
  local install_choice
  while true; do
    read -rp "Do you want to install Keycloak Identity Provider? [y/n]: " install_choice
    case "${install_choice,,}" in
      y|yes)
        return 0
        ;;
      n|no)
        info "Skipping Identity Provider installation."
        return 1
        ;;
      *)
        warn "Please enter 'y' or 'n'."
        ;;
    esac
  done
}

collect_keycloak_variables() {
  echo
  log "Collecting Keycloak configuration..."
  
  # Domain
  KEYCLOAK_DOMAIN=$(prompt_required "Enter domain for Keycloak (e.g., auth.example.com)")
  
  # Admin credentials
  KEYCLOAK_ADMIN=$(prompt_default "Keycloak admin username" "admin")
  KEYCLOAK_ADMIN_PASSWORD=$(prompt_required "Keycloak admin password")
  
  # Database password
  KEYCLOAK_DB_PASSWORD=$(openssl rand -base64 32)
  
  log "Configuration collected."
}

create_keycloak_env() {
  log "Creating Keycloak environment file..."
  cat > "$BASE_DIR/.env" <<EOF
# Keycloak Configuration
KEYCLOAK_DOMAIN=$KEYCLOAK_DOMAIN
KEYCLOAK_ADMIN=$KEYCLOAK_ADMIN
KEYCLOAK_ADMIN_PASSWORD=$KEYCLOAK_ADMIN_PASSWORD

# Database Configuration
KC_DB=postgres
KC_DB_URL=jdbc:postgresql://postgres:5432/keycloak
KC_DB_USERNAME=keycloak
KC_DB_PASSWORD=$KEYCLOAK_DB_PASSWORD

# PostgreSQL Configuration
POSTGRES_DB=keycloak
POSTGRES_USER=keycloak
POSTGRES_PASSWORD=$KEYCLOAK_DB_PASSWORD

# Proxy Configuration
KC_PROXY=edge
KC_HOSTNAME=$KEYCLOAK_DOMAIN
KC_HOSTNAME_STRICT=false
EOF
  chmod 600 "$BASE_DIR/.env"
  log "Environment file created: $BASE_DIR/.env"
}

create_keycloak_compose() {
  log "Creating Keycloak docker-compose.yml..."
  cat > "$BASE_DIR/docker-compose.yml" <<EOF
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    environment:
      - POSTGRES_DB=\${POSTGRES_DB}
      - POSTGRES_USER=\${POSTGRES_USER}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
    volumes:
      - ./postgres:/var/lib/postgresql/data
    networks:
      - keycloak-net
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

  keycloak:
    image: ahmadfaryabkokab/keycloaktailwind:0.0.5
    command: ["start-dev", "--http-enabled=true", "--hostname-strict=false", "--hostname-strict-https=false"]
    environment:
      - KEYCLOAK_ADMIN=\${KEYCLOAK_ADMIN}
      - KEYCLOAK_ADMIN_PASSWORD=\${KEYCLOAK_ADMIN_PASSWORD}
      - KC_DB=postgres
      - KC_DB_URL_HOST=\${KC_DB_URL}
      - KC_DB_URL_DATABASE=\${KC_DB}
      - KC_DB_USERNAME=\${KC_DB_USERNAME}
      - KC_DB_PASSWORD=\${KC_DB_PASSWORD}
      - KC_HOSTNAME_STRICT=false
      - KC_HOSTNAME_STRICT_HTTPS=true
      - KC_HTTP_ENABLED=true
      - KC_HOSTNAME_STRICT_BACKCHANNEL=false
      - KC_METRICS_ENABLED=true
      - KC_PROXY_HEADERS=xforwarded
      - KC_PROXY=edge
      - KC_HOSTNAME=\${KC_HOSTNAME}
      - KC_HEALTH_ENABLED=true
    volumes:
      - ./data:/opt/keycloak/data
    networks:
      - traefik-net
      - keycloak-net
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.swarm.network=traefik-net"
        - "traefik.http.services.kc.loadbalancer.server.port=8080"

        - "traefik.http.middlewares.kc-redirect.redirectscheme.scheme=https"
        - "traefik.http.middlewares.kc-redirect.redirectscheme.permanent=true"

        - "traefik.http.routers.kc.rule=Host(\`${KEYCLOAK_DOMAIN}\`)"
        - "traefik.http.routers.kc.entrypoints=websecure"
        - "traefik.http.routers.kc.tls=true"
        - "traefik.http.routers.kc.service=kc"
        #- "traefik.http.routers.kc.tls.certresolver=le"
        #- "traefik.http.services.kc.loadbalancer.server.port=80"
        - "traefik.http.routers.kc-http.rule=Host(\`${KEYCLOAK_DOMAIN}\`)"
        - "traefik.http.routers.kc-http.entrypoints=web"
        - "traefik.http.routers.kc-http.middlewares=kc-redirect"

    depends_on:
      - postgres
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8080/health/ready || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

networks:
  traefik-net:
    external: true
  keycloak-net:
    driver: overlay
EOF
  
  log "docker-compose.yml created: $BASE_DIR/docker-compose.yml"
}

deploy_keycloak_stack() {
  log "Deploying Keycloak stack..."
  cd "$BASE_DIR"
  docker stack deploy -c docker-compose.yml keycloak
  log "Keycloak stack deployed successfully!"
  echo
  info "Waiting for Keycloak to start (this may take a minute)..."
  sleep 10
  docker service ls | grep keycloak || true
  echo
  info "Keycloak will be available at: https://$KEYCLOAK_DOMAIN"
  info "Admin Console: https://$KEYCLOAK_DOMAIN/admin"
  info "Username: $KEYCLOAK_ADMIN"
  echo
  warn "Note: Keycloak may take 1-2 minutes to fully start. Check with: docker service logs keycloak_keycloak"
}

save_keycloak_config() {
  mkdir -p "$(dirname "$PROGRESS_FILE")"
  
  if [[ ! -f "$PROGRESS_FILE" ]]; then
    echo '{}' > "$PROGRESS_FILE"
  fi
  
  local tmp=$(mktemp)
  jq --arg domain "$KEYCLOAK_DOMAIN" \
    '.identity_provider_installed = true | .identity_provider_domain = $domain' \
    "$PROGRESS_FILE" > "$tmp" && mv "$tmp" "$PROGRESS_FILE"
}

save_skip_config() {
  mkdir -p "$(dirname "$PROGRESS_FILE")"
  
  if [[ ! -f "$PROGRESS_FILE" ]]; then
    echo '{}' > "$PROGRESS_FILE"
  fi
  
  local tmp=$(mktemp)
  jq '.identity_provider_installed = false' "$PROGRESS_FILE" > "$tmp" && mv "$tmp" "$PROGRESS_FILE"
}

main() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "This module must be run as root (use sudo)."
    exit 1
  fi
  
  echo "========================================"
  echo "Module 06: Identity Provider Setup"
  echo "========================================"
  echo
  
  if ! ask_identity_provider_installation; then
    save_skip_config
    log "Module 06 completed (Identity Provider skipped)."
    exit 0
  fi
  
  create_directories
  collect_keycloak_variables
  create_keycloak_env
  create_keycloak_compose
  deploy_keycloak_stack
  save_keycloak_config
  
  log "Module 06 completed successfully."
}

main "$@"

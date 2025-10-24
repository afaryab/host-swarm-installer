#!/usr/bin/env bash
set -euo pipefail

# =========================
# Module 05: Server Manager Setup
# =========================

log() { echo -e "\033[1;32m[+] $*\033[0m"; }
err() { echo -e "\033[1;31m[✗] $*\033[0m"; }
info() { echo -e "\033[1;34m[i] $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }

BASE_DIR="/mnt/hosting/infrastructure/server-manager"
PROGRESS_FILE="/mnt/hosting/infrastructure/.install_progress.json"
SSH_KEY_PATH="/root/.ssh/server_manager_key"

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

create_directories() {
  log "Creating Server Manager directory structure..."
  mkdir -p "$BASE_DIR"/{app,mysql}
  log "Directories created at: $BASE_DIR"
}

generate_ssh_key() {
  if [[ -f "$SSH_KEY_PATH" ]]; then
    info "SSH key already exists at: $SSH_KEY_PATH"
    return
  fi
  
  log "Generating SSH key pair for Server Manager..."
  ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "server-manager@$(hostname)"
  chmod 600 "$SSH_KEY_PATH"
  chmod 644 "${SSH_KEY_PATH}.pub"
  log "SSH key generated: $SSH_KEY_PATH"
  echo
  info "Public key:"
  cat "${SSH_KEY_PATH}.pub"
  echo
}

ask_server_manager_installation() {
  echo "========================================"
  echo "Server Manager Installation"
  echo "========================================"
  echo
  info "Server Manager helps manage multiple servers from a central location."
  echo
  
  local install_choice
  while true; do
    read -rp "Do you want to install Server Manager? [y/n]: " install_choice
    case "${install_choice,,}" in
      y|yes)
        return 0
        ;;
      n|no)
        info "Skipping Server Manager installation."
        return 1
        ;;
      *)
        warn "Please enter 'y' or 'n'."
        ;;
    esac
  done
}

ask_server_manager_mode() {
  
  local choice
  while true; do
    read -rp "Enter your choice [1:create-2:connect]: " choice
    case "$choice" in
      1)
        echo "create"
        return
        ;;
      2)
        echo "connect"
        return
        ;;
      *)
        warn "Invalid choice. Please enter 1 or 2."
        ;;
    esac
  done
}

create_server_manager() {
  log "Setting up new Server Manager instance..."
  echo
  
  # Collect configuration
  local domain
  domain=$(prompt_required "Enter domain for Server Manager (e.g., manager.example.com)")
  
  local db_password
  db_password=$(openssl rand -base64 32)
  
  local admin_email
  admin_email=$(prompt_required "Enter admin email")
  
  local admin_password
  admin_password=$(prompt_required "Enter admin password")
  
  # Generate SSH key
  generate_ssh_key
  
  # Create environment file
  log "Creating environment file..."
  cat > "$BASE_DIR/.env" <<EOF
# Server Manager Configuration
DOMAIN=$domain
ADMIN_EMAIL=$admin_email
ADMIN_PASSWORD=$admin_password

# Database Configuration
DB_HOST=mysql
DB_PORT=3306
DB_DATABASE=server_manager
DB_USERNAME=server_manager
DB_PASSWORD=$db_password

# SSH Configuration
SSH_PRIVATE_KEY_PATH=$SSH_KEY_PATH
SSH_PUBLIC_KEY=$(cat "${SSH_KEY_PATH}.pub")
EOF
  chmod 600 "$BASE_DIR/.env"
  log "Environment file created: $BASE_DIR/.env"
  
  # Create docker-compose.yml
  create_server_manager_compose "$domain"
  
  # Deploy stack
  deploy_server_manager_stack
  
  # Save configuration
  save_server_manager_config "create" "$domain"
  
  echo
  log "Server Manager created successfully!"
  info "Access your Server Manager at: https://$domain"
  info "Admin Email: $admin_email"
}

connect_to_existing_server_manager() {
  log "Connecting to existing Server Manager..."
  echo
  
  warn "You need the Server Manager URL and Connection Key from the manager."
  echo
  
  local manager_url
  manager_url=$(prompt_required "Enter Server Manager URL (e.g. https://manager.example.com)")
  
  # Remove trailing slash if present
  manager_url="${manager_url%/}"
  
  local connection_key
  connection_key=$(prompt_required "Enter Connection Key")
  
  # Generate SSH key for this server
  generate_ssh_key
  
  local public_key
  public_key=$(cat "${SSH_KEY_PATH}.pub")
  
  # Get Server Manager's SSH public key using connection key
  log "Validating connection key and retrieving Server Manager's SSH public key..."
  
  local response
  response=$(curl -s -X POST "${manager_url}/api/server/ssh-key" \
    -H "Content-Type: application/json" \
    -d "{\"connection_key\": \"${connection_key}\"}" || echo "")
  
  if [[ -z "$response" ]]; then
    err "Failed to connect to Server Manager. Please check the URL and connection key."
    exit 1
  fi
  
  # Check for error in response
  local error_msg
  error_msg=$(echo "$response" | jq -r '.error // empty' 2>/dev/null || echo "")
  
  if [[ -n "$error_msg" ]]; then
    err "Server Manager returned error: $error_msg"
    exit 1
  fi
  
  # Extract manager's public key from response
  local manager_public_key
  manager_public_key=$(echo "$response" | jq -r '.public_key // empty' 2>/dev/null || echo "")
  
  if [[ -z "$manager_public_key" ]]; then
    err "Failed to retrieve Server Manager's SSH public key."
    err "Response: $response"
    exit 1
  fi
  
  log "Server Manager's SSH public key retrieved successfully."
  
  # Add manager's public key to authorized_keys
  log "Adding Server Manager's public key to authorized_keys..."
  mkdir -p /root/.ssh
  
  # Check if key already exists
  if grep -q "$manager_public_key" /root/.ssh/authorized_keys 2>/dev/null; then
    info "Server Manager's public key already exists in authorized_keys."
  else
    echo "$manager_public_key" >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    log "Server Manager's public key added to authorized_keys."
  fi
  
  # Now send our public key to the server manager
  log "Sending this server's SSH public key to Server Manager..."
  
  local register_response
  register_response=$(curl -s -X POST "${manager_url}/api/server/register-key" \
    -H "Content-Type: application/json" \
    -d "{
      \"connection_key\": \"${connection_key}\",
      \"ssh_public_key\": \"${public_key}\",
      \"hostname\": \"$(hostname)\",
      \"ip_address\": \"$(hostname -I | awk '{print $1}')\"
    }" || echo "")
  
  if [[ -z "$register_response" ]]; then
    warn "Could not register SSH key with Server Manager."
    warn "You may need to add it manually."
  else
    local register_error
    register_error=$(echo "$register_response" | jq -r '.error // empty' 2>/dev/null || echo "")
    
    if [[ -n "$register_error" ]]; then
      warn "Server Manager returned error during key registration: $register_error"
    else
      log "SSH public key registered successfully with Server Manager."
    fi
  fi
  
  # Save configuration
  save_server_manager_config "connect" "$manager_url"
  
  echo
  log "Successfully connected to Server Manager!"
  info "Server Manager can now SSH into this server."
  info "Manager URL: $manager_url"
  echo
  info "Your server's SSH public key:"
  cat "${SSH_KEY_PATH}.pub"
}

create_server_manager_compose() {
  local domain="$1"
  
  log "Creating Server Manager docker-compose.yml..."
  cat > "$BASE_DIR/docker-compose.yml" <<EOF
version: '3.8'

services:
  app:
    image: ahmadfaryabkokab/host-swarm:latest
    environment:
      - APP_NAME="Host Swarm"
      - APP_ENV=production
      - APP_DEBUG=false
      - DB_CONNECTION=mysql
      - DB_HOST=\${DB_HOST}
      - DB_PORT=\${DB_PORT}
      - DB_DATABASE=\${DB_DATABASE}
      - DB_USERNAME=\${DB_USERNAME}
      - DB_PASSWORD=\${DB_PASSWORD}
      - APP_URL=https://${domain}
    volumes:
      - ./app:/app/storage
      - /root/.ssh/server_manager_key:/app/ssh/id_rsa:ro
    networks:
      - traefik-net
      - server-manager-net
    deploy:
      mode: replicated
      replicas: 1
      labels:
        - "traefik.enable=true"
        - "traefik.swarm.network=traefik-net"
        - "traefik.http.services.server-manager.loadbalancer.server.port=80"

        - "traefik.http.middlewares.server-manager-redirect.redirectscheme.scheme=https"
        - "traefik.http.middlewares.server-manager-redirect.redirectscheme.permanent=true"

        - "traefik.http.routers.server-manager.rule=Host(\\\`${domain}\\\`)"
        - "traefik.http.routers.server-manager.entrypoints=websecure"
        - "traefik.http.routers.server-manager.tls=true"
        - "traefik.http.routers.server-manager.service=server-manager"
        - "traefik.http.routers.server-manager-http.rule=Host(\\\`${domain}\\\`)"
        - "traefik.http.routers.server-manager-http.entrypoints=web"
        - "traefik.http.routers.server-manager-http.service=server-manager-redirect"
        
    depends_on:
      - mysql

  mysql:
    image: ahmadfaryabkokab/mysql8:0.2.0
    init: true
    environment:
      - MYSQL_ROOT_PASSWORD=\${DB_PASSWORD}
      - MYSQL_DATABASE=\${DB_DATABASE}
      - MYSQL_USER=\${DB_USERNAME}
      - MYSQL_PASSWORD=\${DB_PASSWORD}
      - BACKUP_CRON="0 * * * *"          # Every hour at minute 0
      - USAGE_CRON="*/30 * * * *"          # Every half hour
      - PRUNE_CRON="0 4 * * 0"           # Weekly cleanup on Sunday at 4 AM
      - RETAIN_DAYS=1                    # Keep 1 day of backups
      - RETAIN_COUNT=6                   # Keep max 6 backups
    volumes:
      - ./mysql:/var/lib/mysql
    networks:
      - server-manager-net
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
  redis:
    image: redis:7-alpine
    networks:
      - server-manager-net
    deploy:
      restart_policy:
        condition: any

networks:
  traefik-net:
    external: true
  server-manager-net:
    driver: overlay
EOF
  
  log "docker-compose.yml created: $BASE_DIR/docker-compose.yml"
}

deploy_server_manager_stack() {
  log "Deploying Server Manager stack..."
  cd "$BASE_DIR"
  docker stack deploy -c docker-compose.yml server-manager
  log "Server Manager stack deployed successfully!"
  echo
  info "Waiting for Server Manager to start..."
  sleep 5
  docker service ls | grep server-manager || true
}

save_server_manager_config() {
  local mode="$1"
  local info="$2"
  
  mkdir -p "$(dirname "$PROGRESS_FILE")"
  
  if [[ ! -f "$PROGRESS_FILE" ]]; then
    echo '{}' > "$PROGRESS_FILE"
  fi
  
  local tmp=$(mktemp)
  jq --arg mode "$mode" --arg info "$info" \
    '.server_manager_installed = true | .server_manager_mode = $mode | .server_manager_info = $info' \
    "$PROGRESS_FILE" > "$tmp" && mv "$tmp" "$PROGRESS_FILE"
}

save_skip_config() {
  mkdir -p "$(dirname "$PROGRESS_FILE")"
  
  if [[ ! -f "$PROGRESS_FILE" ]]; then
    echo '{}' > "$PROGRESS_FILE"
  fi
  
  local tmp=$(mktemp)
  jq '.server_manager_installed = false' "$PROGRESS_FILE" > "$tmp" && mv "$tmp" "$PROGRESS_FILE"
}

main() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "This module must be run as root (use sudo)."
    exit 1
  fi
  
  echo "========================================"
  echo "Module 05: Server Manager Setup"
  echo "========================================"
  echo
  
  if ! ask_server_manager_installation; then
    save_skip_config
    log "Module 05 completed (Server Manager skipped)."
    exit 0
  fi
  
  create_directories
  
  echo
  info "Server Manager Mode:"
  echo "  1) Create new Server Manager (this will be the central server)"
  echo "  2) Connect to existing Server Manager (this server will be managed)"
  echo
  

  local mode
  mode=$(ask_server_manager_mode)
  log "Selected mode: $mode"
  if [[ "$mode" == "create" ]]; then
    create_server_manager
  else
    connect_to_existing_server_manager
  fi
  
  log "Module 05 completed successfully."
}

main "$@"

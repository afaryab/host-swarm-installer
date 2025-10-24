#!/usr/bin/env bash#!/usr/bin/env bash#!/usr/bin/env bash

set -euo pipefail

set -euo pipefailset -euo pipefail

# =========================

# Host-Swarm Infrastructure Installer

# =========================

# Modular installation orchestrator with progress tracking# =========================# =========================



SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"# Host-Swarm Infrastructure Installer# Host-Swarm Infrastructure

BASE_DIR="/mnt/hosting/infrastructure"

PROGRESS_FILE="$BASE_DIR/.install_progress.json"# =========================# =========================

MODULES_DIR="$SCRIPT_DIR/modules"

# Modular installation orchestrator with progress tracking# This script installs Docker + Swarm, prepares /mnt/hosting/infrastructure,

# Module execution order

declare -a MODULES=(# and resume capability.# asks for domains & ACME email, then deploys a single Swarm stack: "infrastructure".

  "01-docker"

  "02-swarm"# Services: traefik, portainer.

  "03-traefik"

  "04-portainer"PROGRESS_FILE="/mnt/hosting/infrastructure/.install_progress.json"# It also sets up day-wise usage JSON exports for future billing.

  "05-server-manager"

  "06-identity-provider"BASE_URL="${INSTALLER_BASE_URL:-https://raw.githubusercontent.com/afaryab/host-swarm-installer/main/modules}"# No Docker named volumes are used; everything is mounted from local folders.

)



declare -A MODULE_NAMES=(

  ["01-docker"]="Docker Validation and Installation"# Color output functionsrequire_root() {

  ["02-swarm"]="Docker Swarm Setup"

  ["03-traefik"]="Traefik Reverse Proxy"log() { echo -e "\033[1;32m[+] $*\033[0m"; }  if [[ "${EUID}" -ne 0 ]]; then

  ["04-portainer"]="Portainer (Optional)"

  ["05-server-manager"]="Server Manager (Optional)"warn() { echo -e "\033[1;33m[!] $*\033[0m"; }    echo "Please run as root (sudo)." >&2

  ["06-identity-provider"]="Identity Provider (Optional)"

)err() { echo -e "\033[1;31m[✗] $*\033[0m"; }    exit 1



# Color output functionsinfo() { echo -e "\033[1;34m[i] $*\033[0m"; }  fi

log() { echo -e "\033[1;32m[+] $*\033[0m"; }

warn() { echo -e "\033[1;33m[!] $*\033[0m"; }}

err() { echo -e "\033[1;31m[✗] $*\033[0m"; }

info() { echo -e "\033[1;34m[i] $*\033[0m"; }require_root() {



# Check if running as root  if [[ "${EUID}" -ne 0 ]]; thenlog() { echo -e "\033[1;32m[+] $*\033[0m"; }

require_root() {

  if [[ "${EUID}" -ne 0 ]]; then    err "Please run as root (sudo)."warn() { echo -e "\033[1;33m[!] $*\033[0m"; }

    err "This script must be run as root (use sudo)."

    exit 1    exit 1err() { echo -e "\033[1;31m[✗] $*\033[0m"; }

  fi

}  fi



# Initialize progress tracking}prompt_default() {

init_progress() {

  mkdir -p "$BASE_DIR"  local prompt="$1"; local default="$2"; local var

  

  if [[ ! -f "$PROGRESS_FILE" ]]; then# Define installation modules  read -rp "$prompt [$default]: " var || true

    log "Initializing installation progress tracking..."

    cat > "$PROGRESS_FILE" <<EOFdeclare -A MODULES=(  echo "${var:-$default}"

{

  "started_at": "$(date -u +%FT%TZ)",  ["01-docker"]="Docker Engine Installation"}

  "completed": false,

  "modules": {}  ["02-swarm"]="Docker Swarm Initialization"

}

EOF  ["03-directories"]="Directory Structure & Networks"install_docker() {

  fi

}  ["04-traefik"]="Traefik & Portainer Configuration"  if command -v docker >/dev/null 2>&1; then



# Get module status  ["05-keycloak"]="Keycloak & Server Manager (Optional)"    log "Docker already installed."

get_module_status() {

  local module="$1"  ["06-metrics"]="Metrics Collection Setup"    return

  if [[ ! -f "$PROGRESS_FILE" ]]; then

    echo "not-started")  fi

    return

  fi  log "Installing Docker Engine..."

  jq -r ".modules[\"$module\"].status // \"not-started\"" "$PROGRESS_FILE" 2>/dev/null || echo "not-started"

}# Module execution order  if [[ -e /etc/debian_version ]]; then



# Set module statusMODULE_ORDER=("01-docker" "02-swarm" "03-directories" "04-traefik" "05-keycloak" "06-metrics")    apt-get update -y

set_module_status() {

  local module="$1"    apt-get install -y ca-certificates curl gnupg lsb-release

  local status="$2"

  local tmp=$(mktemp)init_progress() {    install -m 0755 -d /etc/apt/keyrings

  

  jq --arg module "$module" \  mkdir -p "$(dirname "$PROGRESS_FILE")"    curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg \

     --arg status "$status" \

     --arg timestamp "$(date -u +%FT%TZ)" \  if [[ ! -f "$PROGRESS_FILE" ]]; then      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

     '.modules[$module] = {status: $status, timestamp: $timestamp}' \

     "$PROGRESS_FILE" > "$tmp" && mv "$tmp" "$PROGRESS_FILE"    log "Initializing installation progress tracking..."    chmod a+r /etc/apt/keyrings/docker.gpg

}

    cat > "$PROGRESS_FILE" <<EOF    echo \

# Mark installation as complete

mark_installation_complete() {{      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \

  local tmp=$(mktemp)

  jq --arg timestamp "$(date -u +%FT%TZ)" \  "started_at": "$(date -u +%FT%TZ)",      https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") \

     '.completed = true | .completed_at = $timestamp' \

     "$PROGRESS_FILE" > "$tmp" && mv "$tmp" "$PROGRESS_FILE"  "completed": false,      $(. /etc/os-release; echo "$VERSION_CODENAME") stable" \

}

  "modules": {}      > /etc/apt/sources.list.d/docker.list

# Check if installation is complete

is_installation_complete() {}    apt-get update -y

  if [[ ! -f "$PROGRESS_FILE" ]]; then

    echo "false"EOF    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin jq

    return

  fi  fi    systemctl enable --now docker

  jq -r '.completed // false' "$PROGRESS_FILE" 2>/dev/null || echo "false"

}}  else



# Get pending modules    err "This installer currently supports Debian/Ubuntu. Please install Docker manually."

get_pending_modules() {

  local pending=()get_module_status() {    exit 1

  for module in "${MODULES[@]}"; do

    local status=$(get_module_status "$module")  local module="$1"  fi

    if [[ "$status" != "completed" ]]; then

      pending+=("$module")  jq -r ".modules[\"$module\"].status // \"not-started\"" "$PROGRESS_FILE"}

    fi

  done}

  echo "${pending[@]}"

}ensure_swarm() {



# Show installation progressset_module_status() {  local swarm_state

show_progress() {

  echo  local module="$1"  swarm_state=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null)

  info "=== Installation Progress ==="

  for module in "${MODULES[@]}"; do  local status="$2"  if [[ "$swarm_state" == "active" ]]; then

    local status=$(get_module_status "$module")

    local desc="${MODULE_NAMES[$module]}"  local tmp=$(mktemp)    log "Docker Swarm already initialized."

    case "$status" in

      completed)  jq --arg module "$module" \  else

        echo -e "  \033[1;32m✓\033[0m $desc"

        ;;     --arg status "$status" \    # figure out advertise address (best effort)

      in-progress)

        echo -e "  \033[1;33m◐\033[0m $desc (in progress)"     --arg timestamp "$(date -u +%FT%TZ)" \    local ip addr_guess

        ;;

      failed)     '.modules[$module] = {status: $status, timestamp: $timestamp}' \    addr_guess=$(hostname -I 2>/dev/null | awk '{print $1}')

        echo -e "  \033[1;31m✗\033[0m $desc (failed)"

        ;;     "$PROGRESS_FILE" > "$tmp" && mv "$tmp" "$PROGRESS_FILE"    ip=$(prompt_default "Advertise IP for Swarm" "${addr_guess:-127.0.0.1}")

      *)

        echo -e "  \033[0;37m○\033[0m $desc"}    log "Initializing Swarm..."

        ;;

    esac    docker swarm init --advertise-addr "$ip" || true

  done

  echomark_installation_complete() {  fi

}

  local tmp=$(mktemp)}

# Execute a module

execute_module() {  jq --arg timestamp "$(date -u +%FT%TZ)" \

  local module="$1"

  local module_script="$MODULES_DIR/${module}.sh"     '.completed = true | .completed_at = $timestamp' \create_dirs() {

  local module_name="${MODULE_NAMES[$module]}"

       "$PROGRESS_FILE" > "$tmp" && mv "$tmp" "$PROGRESS_FILE"  BASE="/mnt/hosting/infrastructure"

  log "Executing: $module_name"

  }  mkdir -p "$BASE/traefik/letsencrypt" \

  set_module_status "$module" "in-progress"

             "$BASE/traefik/dynamic" \

  if [[ -f "$module_script" ]]; then

    if bash "$module_script"; thenis_installation_complete() {           "$BASE/traefik/dynamic/certs" \

      set_module_status "$module" "completed"

      log "Module $module completed successfully."  jq -r '.completed // false' "$PROGRESS_FILE"           "$BASE/portainer/data" \

      return 0

    else}           "$BASE/keycloak/data" \

      set_module_status "$module" "failed"

      err "Module $module failed!"           "$BASE/keycloak/postgres" \

      return 1

    figet_pending_modules() {           "$BASE/server-manager/app" \

  else

    err "Module script not found: $module_script"  local pending=()           "$BASE/server-manager/mysql" \

    set_module_status "$module" "failed"

    return 1  for module in "${MODULE_ORDER[@]}"; do           "$BASE/shared" \

  fi

}    local status=$(get_module_status "$module")           "$BASE/metrics"



# Ask user to continue or start new    if [[ "$status" != "completed" ]]; then  chmod 600 "$BASE/traefik/letsencrypt" || true

ask_continue_or_restart() {

  echo      pending+=("$module")  touch "$BASE/traefik/letsencrypt/acme.json"

  warn "A previous installation is in progress."

  show_progress    fi  chmod 600 "$BASE/traefik/letsencrypt/acme.json"

  echo

  info "What would you like to do?"  done}

  echo "  1) Continue from where it left off"

  echo "  2) Start a new installation (this will reset progress)"  echo "${pending[@]}"

  echo "  3) Exit"

  echo}create_networks() {

  

  while true; do  docker network create --driver overlay traefik-net >/dev/null 2>&1 || true

    read -rp "Enter your choice [1-3]: " choice

    case "$choice" inshow_progress() {}

      1)

        return 0  # Continue  echo

        ;;

      2)  info "=== Installation Progress ==="write_env_and_stack() {

        warn "Resetting installation progress..."

        rm -f "$PROGRESS_FILE"  for module in "${MODULE_ORDER[@]}"; do  local BASE="/mnt/hosting/infrastructure"

        init_progress

        return 0    local status=$(get_module_status "$module")  local ACME_EMAIL="$1"

        ;;

      3)    local desc="${MODULES[$module]}"  local TRAEFIK_HOST="$2"

        info "Installation cancelled."

        exit 0    case "$status" in  local PORTAINER_HOST="$3"

        ;;

      *)      completed)  local WANT_LOCAL_SERVER_MANAGER="$4"

        warn "Invalid choice. Please enter 1, 2, or 3."

        ;;        echo -e "  \033[1;32m✓\033[0m $desc"  local SERVER_MANAGER_DOMAIN="$5"

    esac

  done        ;;  local CF_DNS_API_TOKEN="$6"

}

      in-progress)  local KEYCLOAK_HOST="$7"

# Ask to redo specific section or all

ask_redo_options() {        echo -e "  \033[1;33m⟳\033[0m $desc"  local CF_ORIGIN_KEY="$8"

  echo

  info "Installation is already complete!"        ;;  local CF_ORIGIN_PEM="$9"

  show_progress

  echo      failed)  local KC_USER="${10}"

  info "What would you like to do?"

  echo "  1) Redo specific module"        echo -e "  \033[1;31m✗\033[0m $desc"  local KC_PASS="${11}"

  echo "  2) Redo entire installation"

  echo "  3) Exit"        ;;

  echo

        *)  cat > "$BASE/traefik/dynamic/certs/cf-origin.pem" <<EOF

  while true; do

    read -rp "Enter your choice [1-3]: " choice        echo -e "  \033[1;90m○\033[0m $desc"$CF_ORIGIN_PEM

    case "$choice" in

      1)        ;;EOF

        select_module_to_redo

        return    esac  chmod 644 "$BASE/traefik/dynamic/certs/cf-origin.pem"

        ;;

      2)  done

        warn "Resetting entire installation..."

        rm -f "$PROGRESS_FILE"  echo  cat > "$BASE/traefik/dynamic/certs/cf-origin.key" <<EOF

        init_progress

        run_installation}$CF_ORIGIN_KEY

        return

        ;;EOF

      3)

        info "Exiting."execute_module() {  chmod 600 "$BASE/traefik/dynamic/certs/cf-origin.key"

        exit 0

        ;;  local module="$1"

      *)

        warn "Invalid choice. Please enter 1, 2, or 3."  local desc="${MODULES[$module]}"  cat > "$BASE/traefik/dynamic/tls.yml" <<EOF

        ;;

    esac  tls:

  done

}  log "Starting: $desc"  certificates:



# Select specific module to redo  set_module_status "$module" "in-progress"    - certFile: /dynamic/certs/cf-origin.pem

select_module_to_redo() {

  echo        keyFile: /dynamic/certs/cf-origin.key

  info "Select a module to redo:"

  echo  # Execute module scriptEOF

  

  local i=1  local script_url="${BASE_URL}/${module}.sh"

  for module in "${MODULES[@]}"; do

    echo "  $i) ${MODULE_NAMES[$module]}"  local local_script="./modules/${module}.sh"  # Generate docker-compose.yml with inlined values (no .env file)

    ((i++))

  done    cat > "$BASE/docker-compose.yml" <<STACK

  echo "  $i) Back to main menu"

  echo  # Try local file first, fall back to URLversion: "3.9"

  

  while true; do  if [[ -f "$local_script" ]]; then

    read -rp "Enter your choice [1-$i]: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$i" ]; then    info "Executing local module: $local_script"networks:

      if [ "$choice" -eq "$i" ]; then

        ask_redo_options    if bash "$local_script"; then  traefik-net:

        return

      fi      set_module_status "$module" "completed"    external: true

      

      local selected_module="${MODULES[$((choice-1))]}"      log "Completed: $desc"  keycloak-net:

      log "Re-executing: ${MODULE_NAMES[$selected_module]}"

      set_module_status "$selected_module" "not-started"      return 0    driver: overlay

      execute_module "$selected_module"

          else  server-manager-net:

      echo

      info "Module re-execution complete."      set_module_status "$module" "failed"    driver: overlay

      read -rp "Press Enter to return to menu..." dummy

      ask_redo_options      err "Failed: $desc"

      return

    else      return 1services:

      warn "Invalid choice. Please enter a number between 1 and $i."

    fi    fi

  done

}  else  # ----------------



# Run installation    info "Downloading and executing: $script_url"  # Traefik (edge)

run_installation() {

  log "Starting installation process..."    if curl -fsSL "$script_url" | bash; then  # ----------------

  echo

        set_module_status "$module" "completed"  traefik:

  local failed=false

        log "Completed: $desc"    image: traefik:v3.4

  for module in "${MODULES[@]}"; do

    local status=$(get_module_status "$module")      return 0    command:

    

    if [[ "$status" == "completed" ]]; then    else      - --providers.swarm=true

      info "Skipping ${MODULE_NAMES[$module]} (already completed)"

      continue      set_module_status "$module" "failed"      - --providers.swarm.network=traefik-net

    fi

          err "Failed: $desc"      - --providers.swarm.exposedByDefault=false

    echo

    log "========================================"       return 1      - --providers.file.directory=/dynamic

    log "Starting: ${MODULE_NAMES[$module]}"

    log "========================================"    fi      - --providers.file.watch=true

    echo

      fi      - --entrypoints.web.address=:80

    if ! execute_module "$module"; then

      failed=true}      - --entrypoints.websecure.address=:443

      err "Installation failed at module: $module"

      echo      - --entrypoints.traefik.address=:8080

      warn "You can re-run this script to continue from this point."

      breakprompt_continue_or_restart() {      - --api.dashboard=true

    fi

  done  show_progress      # - --certificatesresolvers.le.acme.httpchallenge.entrypoint=web

  

  if [[ "$failed" == "false" ]]; then        - --certificatesresolvers.le.acme.email=${ACME_EMAIL}

    mark_installation_complete

    echo  local pending=$(get_pending_modules)      - --certificatesresolvers.le.acme.storage=/letsencrypt/acme.json

    log "========================================"

    log "Installation Complete!"  if [[ -n "$pending" ]]; then      - --certificatesresolvers.le.acme.dnschallenge.provider=cloudflare

    log "========================================"

    echo    warn "Previous installation is incomplete."      - --certificatesresolvers.le.acme.dnschallenge.delaybeforecheck=0

    info "All modules have been installed successfully."

    show_progress    echo "What would you like to do?"      - --serversTransport.insecureSkipVerify=false

  fi

}    echo "  1) Continue from where it left off"      - --log.level=INFO



# Display welcome banner    echo "  2) Start fresh (clear all progress)"      - --accesslog=true

show_banner() {

  cat <<'EOF'    echo "  3) Exit"    ports:

╔════════════════════════════════════════════════════════════╗

║                                                            ║    read -rp "Choose [1-3]: " choice      - target: 80

║        HOST-SWARM INFRASTRUCTURE INSTALLER                 ║

║                                                            ║            published: 80

║  Automated Docker Swarm infrastructure deployment          ║

║  with Traefik, Portainer, and optional services            ║    case "$choice" in        protocol: tcp

║                                                            ║

╚════════════════════════════════════════════════════════════╝      1)        mode: host

EOF

  echo        log "Continuing previous installation..."      - target: 443

}

        return 0        published: 443

# Main function

main() {        ;;        protocol: tcp

  require_root

        2)        mode: host

  show_banner

          warn "Starting fresh installation..."      - target: 8080

  init_progress

          # Clear progress but keep directory structure        published: 8080

  # Check if installation is already complete

  local completed=$(is_installation_complete)        rm -f "$PROGRESS_FILE"        protocol: tcp

  

  if [[ "$completed" == "true" ]]; then        init_progress        mode: host

    ask_redo_options

  else        return 0    volumes:

    # Check if there's pending installation

    local pending=$(get_pending_modules)        ;;      - /var/run/docker.sock:/var/run/docker.sock:ro

    

    if [[ -n "$pending" ]] && [[ -f "$PROGRESS_FILE" ]]; then      3|*)      - /mnt/hosting/infrastructure/traefik/letsencrypt:/letsencrypt

      ask_continue_or_restart

    fi        info "Installation cancelled."      - /mnt/hosting/infrastructure/traefik/dynamic:/dynamic

    

    run_installation        exit 0    networks:

  fi

          ;;      - traefik-net

  echo

  log "Thank you for using Host-Swarm Installer!"    esac    environment:

  echo

}  fi      - CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN}



# Handle script interruption}    deploy:

trap 'echo; warn "Installation interrupted. Run this script again to continue."; exit 1' INT TERM

      mode: replicated

main "$@"

prompt_redo_sections() {      replicas: 1

  show_progress      placement:

          constraints: [node.role == manager]

  echo      labels:

  echo "Installation is already complete. What would you like to do?"        - "traefik.enable=true"

  echo "  1) Redo specific section(s)"        - "traefik.swarm.network=traefik-net"

  echo "  2) Redo entire installation"        - "traefik.http.routers.traefik.rule=Host(\`${TRAEFIK_HOST}\`)"

  echo "  3) Exit"        - "traefik.http.routers.traefik.entrypoints=websecure"

  read -rp "Choose [1-3]: " choice        - "traefik.http.routers.traefik.service=api@internal"

          - "traefik.http.routers.traefik.tls=true"

  case "$choice" in        # - "traefik.http.routers.traefik.tls.certresolver=le"

    1)        - "traefik.http.services.traefik.loadbalancer.server.port=8080"

      echo        # - "traefik.http.routers.http-catchall.rule=HostRegexp(\`{host:.+}\`)"

      echo "Select sections to redo (space-separated numbers):"        # - "traefik.http.routers.http-catchall.entrypoints=web"

      local i=1        # - "traefik.http.routers.http-catchall.middlewares=redirect-to-https"

      declare -A module_map        - "traefik.http.routers.traefik-http.rule=Host(\`${TRAEFIK_HOST}\`)"

      for module in "${MODULE_ORDER[@]}"; do        - "traefik.http.routers.traefik-http.entrypoints=web"

        echo "  $i) ${MODULES[$module]}"        - "traefik.http.routers.traefik-http.middlewares=redirect-to-https"

        module_map[$i]="$module"        - "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https"

        ((i++))

      done  # ----------------

      echo  # Portainer

      read -rp "Enter numbers (e.g., 1 3 5): " selections  # ----------------

        portainer:

      local modules_to_redo=()    image: portainer/portainer-ce:latest

      for num in $selections; do    environment:

        if [[ -n "${module_map[$num]:-}" ]]; then      - EDGE_INACTIVITY_TIMEOUT=0

          modules_to_redo+=("${module_map[$num]}")    volumes:

        fi      - /var/run/docker.sock:/var/run/docker.sock:ro

      done      - /mnt/hosting/infrastructure/portainer/data:/data

          networks:

      if [[ ${#modules_to_redo[@]} -eq 0 ]]; then      - traefik-net

        err "No valid sections selected."    deploy:

        exit 1      mode: replicated

      fi      replicas: 1

            placement:

      warn "Will redo: ${modules_to_redo[*]}"        constraints: [node.role == manager]

      read -rp "Confirm? [y/N]: " confirm      labels:

      if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then        - "traefik.enable=true"

        info "Cancelled."        - "traefik.swarm.network=traefik-net"

        exit 0        - "traefik.http.middlewares.port-redirect.redirectscheme.scheme=https"

      fi        - "traefik.http.middlewares.port-redirect.redirectscheme.permanent=true"

              - "traefik.http.routers.port.rule=Host(\`${PORTAINER_HOST}\`)"

      # Reset selected modules        - "traefik.http.routers.port.entrypoints=websecure"

      for module in "${modules_to_redo[@]}"; do        - "traefik.http.routers.port.tls=true"

        set_module_status "$module" "not-started"        # - "traefik.http.routers.port.tls.certresolver=le"

      done        - "traefik.http.services.port.loadbalancer.server.port=9000"

              - "traefik.http.routers.port-http.rule=Host(\`${PORTAINER_HOST}\`)"

      # Mark installation as incomplete        - "traefik.http.routers.port-http.entrypoints=web"

      local tmp=$(mktemp)        - "traefik.http.routers.port-http.middlewares=port-redirect"

      jq '.completed = false' "$PROGRESS_FILE" > "$tmp" && mv "$tmp" "$PROGRESS_FILE"

      STACK

      return 0

      ;;  # Add Keycloak services only if server manager is wanted

    2)  if [[ "$WANT_LOCAL_SERVER_MANAGER" == "yes" ]]; then

      warn "This will redo the entire installation."    cat >> "$BASE/docker-compose.yml" <<KEYCLOAK_STACK

      read -rp "Confirm? [y/N]: " confirm

      if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then  # ----------------

        info "Cancelled."  # Keycloak + Postgres

        exit 0  # ----------------

      fi  keycloak:

          image: quay.io/keycloak/keycloak:latest

      # Ask about clearing data    environment:

      echo      KC_DB: postgres

      echo "Do you want to:"      KC_DB_URL: jdbc:postgresql://keycloak-db:5432/keycloak

      echo "  1) Keep existing data (update configuration only)"      KC_DB_USERNAME: keycloak

      echo "  2) Clear all data and start completely fresh"      KC_DB_PASSWORD: keycloak

      read -rp "Choose [1-2]: " data_choice      KC_HOSTNAME: ${KEYCLOAK_HOST}

            KC_HTTP_ENABLED: "true"

      if [[ "$data_choice" == "2" ]]; then      KC_METRICS_ENABLED: "true"

        warn "Stopping services and clearing data..."      KC_PROXY_HEADERS: xforwarded

        docker stack rm infrastructure 2>/dev/null || true      KC_BOOTSTRAP_ADMIN_USERNAME: ${KC_USER}

        sleep 5      KC_BOOTSTRAP_ADMIN_PASSWORD: ${KC_PASS}

        docker system prune -af --volumes || true    command: ["start"]

        rm -rf /mnt/hosting/infrastructure/* || true    volumes:

      fi      - /mnt/hosting/infrastructure/keycloak/data:/opt/keycloak/data

          depends_on:

      rm -f "$PROGRESS_FILE"      - keycloak-db

      init_progress    networks:

      return 0      - keycloak-net

      ;;      - traefik-net

    3|*)    deploy:

      info "Exiting."      replicas: 1

      exit 0      placement:

      ;;        constraints: [node.role == manager]

  esac      resources:

}        limits:

          cpus: "1"

run_installation() {          memory: 1024M

  for module in "${MODULE_ORDER[@]}"; do        reservations:

    local status=$(get_module_status "$module")          cpus: "0.25"

              memory: 128M

    if [[ "$status" == "completed" ]]; then      labels:

      info "Skipping (already completed): ${MODULES[$module]}"        - "traefik.enable=true"

      continue        - "traefik.swarm.network=traefik-net"

    fi        - "traefik.http.middlewares.kc-redirect.redirectscheme.scheme=https"

            - "traefik.http.middlewares.kc-redirect.redirectscheme.permanent=true"

    if ! execute_module "$module"; then        - "traefik.http.routers.kc.rule=Host(\`${KEYCLOAK_HOST}\`)"

      err "Installation failed at module: ${MODULES[$module]}"        - "traefik.http.routers.kc.entrypoints=websecure"

      err "You can resume by running this script again."        - "traefik.http.routers.kc.tls=true"

      exit 1        - "traefik.http.routers.kc.tls.certresolver=le"

    fi        - "traefik.http.services.kc.loadbalancer.server.port=8080"

  done        - "traefik.http.routers.kc-http.rule=Host(\`${KEYCLOAK_HOST}\`)"

          - "traefik.http.routers.kc-http.entrypoints=web"

  mark_installation_complete        - "traefik.http.routers.kc-http.middlewares=kc-redirect"

  

  echo  keycloak-db:

  echo "========================================="    image: postgres:15

  log "Installation completed successfully!"    environment:

  echo "========================================="      POSTGRES_DB: keycloak

  echo      POSTGRES_USER: keycloak

        POSTGRES_PASSWORD: keycloak

  # Show deployed services    volumes:

  if [[ -f "/mnt/hosting/infrastructure/.install_config.json" ]]; then      - /mnt/hosting/infrastructure/keycloak/postgres:/var/lib/postgresql/data

    local config="/mnt/hosting/infrastructure/.install_config.json"    networks:

    log "Services deployed:"      - keycloak-net

    echo    deploy:

          placement:

    local primary=$(jq -r '.PRIMARY_DOMAIN // ""' "$config")        constraints: [node.role == manager]

    local traefik=$(jq -r '.TRAEFIK_HOST // ""' "$config")

    local portainer=$(jq -r '.PORTAINER_HOST // ""' "$config")  # ----------------

    local keycloak=$(jq -r '.KEYCLOAK_HOST // ""' "$config")  # Server Manager + Mysql

    local manager=$(jq -r '.SERVER_MANAGER_DOMAIN // ""' "$config")  # ----------------

      server-manager:

    [[ -n "$primary" ]] && echo "  Primary Domain:   https://$primary"    image: ahmadfaryabkokab/host-swarm:0.0.6

    [[ -n "$traefik" ]] && echo "  Traefik:          https://$traefik"    environment:

    [[ -n "$portainer" ]] && echo "  Portainer:        https://$portainer"      - APP_NAME=Host-Swarm

    [[ -n "$keycloak" ]] && echo "  Keycloak:         https://$keycloak"      - APP_ENV=production

    [[ -n "$manager" ]] && echo "  Server Manager:   https://$manager"      - APP_DEBUG=false

    echo      - APP_URL=https://${SERVER_MANAGER_DOMAIN}

  fi      - DB_CONNECTION=mysql

        - DB_HOST=server-manager-mysql

  warn "Remember to configure DNS records for your domains."      - DB_PORT=3306

  echo      - DB_DATABASE=hostswarm

}      - DB_USERNAME=hostswarm

      - DB_PASSWORD=hostswarmpassword

main() {      - BROADCAST_DRIVER=pusher

  require_root      - BROADCAST_CONNECTION=pusher

        - QUEUE_CONNECTION=database

  echo "========================================="      - CACHE_STORE=database

  echo "  Host-Swarm Infrastructure Installer"      - REDIS_CLIENT=phpredis

  echo "========================================="      - REDIS_HOST=server-manager-redis

  echo      - REDIS_PASSWORD=null

        - REDIS_PORT=6379

  init_progress      - MAIL_MAILER=smtp

        - MAIL_HOST=smtp.mailtrap.io

  local is_complete=$(is_installation_complete)      - MAIL_PORT=2525

        - MAIL_USERNAME=null

  if [[ "$is_complete" == "true" ]]; then      - MAIL_PASSWORD=null

    prompt_redo_sections      - MAIL_ENCRYPTION=null

  else      - MAIL_FROM_ADDRESS=admin@${SERVER_MANAGER_DOMAIN}

    local pending=$(get_pending_modules)      - MAIL_FROM_NAME=Host Swarm

    if [[ -n "$pending" ]]; then      - GITHUB_CLIENT_ID=null

      prompt_continue_or_restart      - GITHUB_CLIENT_SECRET=null

    fi      - GOOGLE_CLIENT_ID=null

  fi      - GOOGLE_CLIENT_SECRET=null

        - GITLAB_CLIENT_ID=null

  run_installation      - GITLAB_CLIENT_SECRET=null

}      - PADDLE_CLIENT_SIDE_TOKEN=null

      - PADDLE_API_KEY=your-paddle-api-key

main "$@"      - PADDLE_RETAIN_KEYS=your-paddle-retain-key

      - PADDLE_WEBHOOK_SECRET=your-paddle-webhook-secret
      - PADDLE_SANDBOX=true
      - CLOUDFLARE_EMAIL=null
      - CLOUDFLARE_API_KEY=null
      - CLOUDFLARE_ZONE_ID=null
      - CLOUDFLARE_TARGET_IP=null
      - STRIPE_KEY=null
      - STRIPE_SECRET=null
      - STRIPE_WEBHOOK_SECRET=null
    command: ["start"]
    volumes:
      - /mnt/hosting/infrastructure/keycloak/data:/opt/keycloak/data
    depends_on:
      - keycloak-db
    networks:
      - server-manager-net
      - traefik-net
    deploy:
      replicas: 1
      placement:
        constraints: [node.role == manager]
      labels:
        - "traefik.enable=true"
        - "traefik.swarm.network=traefik-net"
        - "traefik.http.middlewares.server-manager-redirect.redirectscheme.scheme=https"
        - "traefik.http.middlewares.server-manager-redirect.redirectscheme.permanent=true"
        - "traefik.http.routers.server-manager.rule=Host(\`${SERVER_MANAGER_DOMAIN}\`)"
        - "traefik.http.routers.server-manager.entrypoints=websecure"
        - "traefik.http.routers.server-manager.tls=true"
        - "traefik.http.routers.server-manager.tls.certresolver=le"
        - "traefik.http.services.server-manager.loadbalancer.server.port=8080"
        - "traefik.http.routers.server-manager-http.rule=Host(\`${SERVER_MANAGER_DOMAIN}\`)"
        - "traefik.http.routers.server-manager-http.entrypoints=web"
        - "traefik.http.routers.server-manager-http.middlewares=server-manager-redirect"

  server-manager-mysql:
    image: ahmadfaryabkokab/mysql8:0.2.0
    init: true
    environment:
      MYSQL_ROOT_PASSWORD: rootpassword
      MYSQL_DATABASE: hostswarm
      MYSQL_USER: hostswarm
      MYSQL_PASSWORD: hostswarmpassword
      MYSQL_ALLOW_EMPTY_PASSWORD: "no"
      BACKUP_CRON: "0 * * * *"          # Every hour at minute 0
      USAGE_CRON: "*/30 * * * *"          # Every half hour
      PRUNE_CRON: "0 4 * * 0"           # Weekly cleanup on Sunday at 4 AM
      RETAIN_DAYS: 1                    # Keep 1 day of backups
      RETAIN_COUNT: 6                   # Keep max 6 backups
    volumes:
      - /mnt/hosting/infrastructure/server-manager/mysql:/var/lib/mysql
    networks:
      - server-manager-net
    deploy:
      placement:
        constraints: [node.role == manager]

  server-manager-redis:
    image: redis:7-alpine
    networks:
      - server-manager-net
    restart: unless-stopped

  
  server-manager-soketi:
    image: 'quay.io/soketi/soketi:1.4-16-alpine'
    environment:
      SOKETI_DEBUG: '1'
      SOKETI_METRICS_SERVER_PORT: '9601'
      SOKETI_DEFAULT_APP_ID: 'app-id'
      SOKETI_DEFAULT_APP_KEY: 'app-key'
      SOKETI_DEFAULT_APP_SECRET: 'app-secret'
      SOKETI_DEFAULT_APP_ENABLE_CLIENT_MESSAGES: 'true'
      SOKETI_DEFAULT_APP_ENABLED: 'true'
      SOKETI_DEFAULT_APP_MAX_CONNECTIONS: '100'
      SOKETI_DEFAULT_APP_MAX_BACKEND_EVENTS_PER_SEC: '100'
      SOKETI_DEFAULT_APP_MAX_CLIENT_EVENTS_PER_SEC: '100'
      SOKETI_DEFAULT_APP_MAX_READ_REQ_PER_SEC: '100'
      # Allow all origins for development
      SOKETI_CORS_ALLOWED_ORIGINS: '*'
      SOKETI_CORS_ALLOWED_HEADERS: '*'
      SOKETI_CORS_ALLOWED_METHODS: '*'
    networks:
      - server-manager-net
    restart: unless-stopped
    deploy:
      replicas: 1
      placement:
        constraints: [node.role == manager]
      labels:
        - "traefik.enable=true"
        - "traefik.swarm.network=traefik-net"

        - "traefik.http.middlewares.ws-server-manager-redirect.redirectscheme.scheme=https"
        - "traefik.http.middlewares.ws-server-manager-redirect.redirectscheme.permanent=true"
        - "traefik.http.routers.ws-server-manager.rule=Host(\`ws-${SERVER_MANAGER_DOMAIN}\`)"
        - "traefik.http.routers.ws-server-manager.entrypoints=websecure"
        - "traefik.http.routers.ws-server-manager.tls=true"
        - "traefik.http.routers.ws-server-manager.tls.certresolver=le"
        - "traefik.http.services.ws-server-manager.loadbalancer.server.port=6001"
        - "traefik.http.routers.ws-server-manager-http.rule=Host(\`ws-${SERVER_MANAGER_DOMAIN}\`)"
        - "traefik.http.routers.ws-server-manager-http.entrypoints=web"
        - "traefik.http.routers.ws-server-manager-http.middlewares=ws-server-manager-redirect"


        - "traefik.http.middlewares.wsm-server-manager-redirect.redirectscheme.scheme=https"
        - "traefik.http.middlewares.wsm-server-manager-redirect.redirectscheme.permanent=true"
        - "traefik.http.routers.wsm-server-manager.rule=Host(\`wsm-${SERVER_MANAGER_DOMAIN}\`)"
        - "traefik.http.routers.wsm-server-manager.entrypoints=websecure"
        - "traefik.http.routers.wsm-server-manager.tls=true"
        - "traefik.http.routers.wsm-server-manager.tls.certresolver=le"
        - "traefik.http.services.wsm-server-manager.loadbalancer.server.port=9601"
        - "traefik.http.routers.wsm-server-manager-http.rule=Host(\`ws-${SERVER_MANAGER_DOMAIN}\`)"
        - "traefik.http.routers.wsm-server-manager-http.entrypoints=web"
        - "traefik.http.routers.wsm-server-manager-http.middlewares=wsm-server-manager-redirect"

KEYCLOAK_STACK
  fi
}

deploy_stack() {
  local BASE="/mnt/hosting/infrastructure"
  log "Deploying stack 'infrastructure'..."
  docker stack deploy -c "$BASE/docker-compose.yml" --with-registry-auth infrastructure
}

setup_metrics_timer() {
  local BASE="/mnt/hosting/infrastructure"
  cat > "$BASE/metrics/collect_usage.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

OUTDIR="/mnt/hosting/infrastructure/metrics"
DATE=$(date -u +%F)
OUT="${OUTDIR}/${DATE}.json"

collect() {
  # Per-stack snapshot of services & tasks with resource specs and image sizes.
  # Live CPU/mem are point-in-time (stats) – acceptable for daily snapshots.
  tmp=$(mktemp)

  # Services in the 'infrastructure' stack
  docker service ls --format '{{.ID}} {{.Name}} {{.Replicas}} {{.Image}}' \
    | awk '$2 ~ /^infrastructure_/ {print}' > "$tmp"

  jq -n --arg date "$(date -u +%FT%TZ)" --arg stack "infrastructure" '{date:$date, stack:$stack, services:[]}' > "$OUT"

  while read -r id name replicas image; do
    # Task count & node placement
    tasks=$(docker service ps --no-trunc --format '{{.ID}} {{.Node}} {{.DesiredState}} {{.CurrentState}}' "$id" | wc -l)

    # Inspect service for resources
    spec=$(docker service inspect "$id" --format '{{json .Spec.TaskTemplate.Resources}}')
    if [[ -z "$spec" ]]; then spec='{}'; fi

    # One running container stat sample (if any)
    cid=$(docker ps --filter "name=$(echo "$name" | sed 's/_/./g')" --format '{{.ID}}' | head -n1 || true)
    cpu="null"; mem="null"
    if [[ -n "${cid}" ]]; then
      # Read one-line stats without stream
      line=$(docker stats --no-stream --format '{{.CPUPerc}} {{.MemUsage}}' "$cid" || true)
      cpu=$(echo "$line" | awk '{print $1}' | tr -d '%')
      mem=$(echo "$line" | awk '{print $2}')
      cpu=${cpu:-null}
      mem=${mem:-null}
    fi

    jq --arg name "$name" \
       --arg image "$image" \
       --arg replicas "$replicas" \
       --argjson resources "$spec" \
       --argjson cpu "$( [[ "$cpu" == "null" ]] && echo null || jq -n "$cpu" )" \
       --arg mem "$mem" \
       '.services += [ {name:$name, image:$image, replicas:$replicas, resources:$resources, sample_cpu_percent:$cpu, sample_mem:$mem} ]' \
       "$OUT" > "${OUT}.tmp" && mv "${OUT}.tmp" "$OUT"
  done < "$tmp"

  rm -f "$tmp"
}
collect
EOS
  chmod +x "$BASE/metrics/collect_usage.sh"

  cat > /etc/systemd/system/host-swarm-usage.service <<'UNIT'
[Unit]
Description=Collect daily usage snapshot for infrastructure stack

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash /mnt/hosting/infrastructure/metrics/collect_usage.sh
UNIT

  cat > /etc/systemd/system/host-swarm-usage.timer <<'UNIT'
[Unit]
Description=Run daily usage snapshot at 00:05 UTC

[Timer]
OnCalendar=*-*-* 00:05:00
Persistent=true

[Install]
WantedBy=timers.target
UNIT

  systemctl daemon-reload
  systemctl enable --now host-swarm-usage.timer
  log "Usage collection timer enabled (writes JSON to /mnt/hosting/infrastructure/metrics/YYYY-MM-DD.json)."
}

main() {
  require_root
  install_docker
  ensure_swarm

  # Check for existing installation
  local BASE="/mnt/hosting/infrastructure"
  if [[ -d "$BASE" && -f "$BASE/docker-compose.yml" ]]; then
    warn "Existing installation detected in $BASE."
    echo "What would you like to do?"
    echo "  1) Update existing deployment (regenerate docker-compose.yml and redeploy)"
    echo "  2) Clear previous installation completely and redeploy"
    echo "  3) Abort installation"
    choice=$(prompt_default "Choose 1, 2, or 3" "1")
    
    case "$choice" in
      1)
        log "Updating existing deployment..."
        # For updates, we'll collect the configuration and then regenerate
        ;;
      2)
        log "Stopping and removing existing stack..."
        docker stack rm infrastructure || true
        log "Removing old Docker networks..."
        docker network rm traefik-net keycloak-net server-manager-net >/dev/null 2>&1 || true
        log "Pruning all unused Docker resources..."
        docker system prune -af --volumes
        sleep 5
        log "Removing old files..."
        rm -rf "$BASE"/*
        log "Old installation cleared."
        ;;
      3|*)
        err "Aborting installation."
        exit 1
        ;;
    esac
  fi

  create_dirs
  create_networks

  echo
  echo "=== Domain & ACME configuration ==="
  PRIMARY_DOMAIN=$(prompt_default "Primary domain for setup" "example.com")
  ACME_EMAIL=$(prompt_default "Email for Let's Encrypt/ACME" "admin@${PRIMARY_DOMAIN}")

  # Service domain configuration with primary domain defaults
  TRAEFIK_HOST=$(prompt_default "Traefik dashboard domain" "traefik.${PRIMARY_DOMAIN}")
  PORTAINER_HOST=$(prompt_default "Portainer domain" "portainer.${PRIMARY_DOMAIN}")
  KEYCLOAK_HOST=$(prompt_default "KeyCloak domain" "login.${PRIMARY_DOMAIN}")
  KEYCLOAK_ADMIN=$(prompt_default "KeyCloak admin" "admin")
  KEYCLOAK_PASSWORD=$(prompt_default "KeyCloak password" "admin")
  CF_DNS_API_TOKEN=$(prompt_default "Cloudflare token" "")
  echo "Paste Cloudflare Origin CA key (Key format), then Ctrl-D:"
  CF_ORIGIN_KEY=$(cat)
  echo "Paste Cloudflare Origin CA cert (PEM format), then Ctrl-D:"
  CF_ORIGIN_PEM=$(cat)

  echo
  echo "=== Server Manager placeholders ==="
  echo "Do you want to setup server manager?"
  CHOICE=$(prompt_default "Choose yes or no" "yes")
  SERVER_MANAGER_DOMAIN="";
  if [[ "$CHOICE" == "yes" ]]; then
    SERVER_MANAGER_DOMAIN=$(prompt_default "Server Manager domain" "manager.${PRIMARY_DOMAIN}")
  fi

  write_env_and_stack "$ACME_EMAIL" "$TRAEFIK_HOST" "$PORTAINER_HOST" "$CHOICE" "$SERVER_MANAGER_DOMAIN" "$CF_DNS_API_TOKEN" "$KEYCLOAK_HOST" "$CF_ORIGIN_KEY" "$CF_ORIGIN_PEM" "$KEYCLOAK_ADMIN" "$KEYCLOAK_PASSWORD"

  deploy_stack
  setup_metrics_timer

  echo
  log "All set! Services are now available:"
  log "Primary Domain:  https://${PRIMARY_DOMAIN}"
  log "Traefik:         https://${TRAEFIK_HOST}"
  log "Portainer:       https://${PORTAINER_HOST}"
  if [[ "$CHOICE" == "yes" ]]; then
    log "Keycloak:        https://${KEYCLOAK_HOST} (${KEYCLOAK_ADMIN}/${KEYCLOAK_PASSWORD})"
    log "Server Manager:  https://${SERVER_MANAGER_DOMAIN} (setup wizard on first visit)"
  fi
  echo
  warn "Remember to point service domains to this host (A/AAAA records) in your DNS provider."
  warn "Primary domain: ${PRIMARY_DOMAIN}"
}

main "$@"

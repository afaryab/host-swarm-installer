#!/usr/bin/env bash
set -euo pipefail

# =========================
# Host-Swarm Infrastructure Installer
# =========================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="/mnt/hosting/infrastructure"
PROGRESS_FILE="$BASE_DIR/.install_progress.json"
MODULES_DIR="$SCRIPT_DIR/modules"
BASE_URL="https://raw.githubusercontent.com/afaryab/host-swarm-installer/main/modules"

declare -a MODULES=(
  "01-docker"
  "02-swarm"
  "03-traefik"
  "04-portainer"
  "05-server-manager"
  "06-identity-provider"
)

declare -A MODULE_NAMES=(
  ["01-docker"]="Docker Validation and Installation"
  ["02-swarm"]="Docker Swarm Setup"
  ["03-traefik"]="Traefik Reverse Proxy"
  ["04-portainer"]="Portainer (Optional)"
  ["05-server-manager"]="Server Manager (Optional)"
  ["06-identity-provider"]="Identity Provider (Optional)"
)

log() { echo -e "\033[1;32m[+] $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }
err() { echo -e "\033[1;31m[✗] $*\033[0m"; }
info() { echo -e "\033[1;34m[i] $*\033[0m"; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "This script must be run as root (use sudo)."
    exit 1
  fi
}

init_progress() {
  mkdir -p "$BASE_DIR"
  if [[ ! -f "$PROGRESS_FILE" ]]; then
    log "Initializing installation progress tracking..."
    cat > "$PROGRESS_FILE" <<EOF
{
  "started_at": "$(date -u +%FT%TZ)",
  "completed": false,
  "modules": {}
}
EOF
  fi
}

get_module_status() {
  local module="$1"
  if [[ ! -f "$PROGRESS_FILE" ]]; then
    echo "not-started"
    return
  fi
  jq -r ".modules[\"$module\"].status // \"not-started\"" "$PROGRESS_FILE" 2>/dev/null || echo "not-started"
}

set_module_status() {
  local module="$1"
  local status="$2"
  local tmp=$(mktemp)
  jq --arg module "$module" \
     --arg status "$status" \
     --arg timestamp "$(date -u +%FT%TZ)" \
     '.modules[$module] = {status: $status, timestamp: $timestamp}' \
     "$PROGRESS_FILE" > "$tmp" && mv "$tmp" "$PROGRESS_FILE"
}

mark_installation_complete() {
  local tmp=$(mktemp)
  jq --arg timestamp "$(date -u +%FT%TZ)" \
     '.completed = true | .completed_at = $timestamp' \
     "$PROGRESS_FILE" > "$tmp" && mv "$tmp" "$PROGRESS_FILE"
}

is_installation_complete() {
  if [[ ! -f "$PROGRESS_FILE" ]]; then
    echo "false"
    return
  fi
  jq -r '.completed // false' "$PROGRESS_FILE" 2>/dev/null || echo "false"
}

get_pending_modules() {
  local pending=()
  for module in "${MODULES[@]}"; do
    local status=$(get_module_status "$module")
    if [[ "$status" != "completed" ]]; then
      pending+=("$module")
    fi
  done
  echo "${pending[@]}"
}

show_progress() {
  echo
  info "=== Installation Progress ==="
  for module in "${MODULES[@]}"; do
    local status=$(get_module_status "$module")
    local desc="${MODULE_NAMES[$module]}"
    case "$status" in
      completed) echo -e "  \033[1;32m✓\033[0m $desc" ;;
      in-progress) echo -e "  \033[1;33m◐\033[0m $desc (in progress)" ;;
      failed) echo -e "  \033[1;31m✗\033[0m $desc (failed)" ;;
      *) echo -e "  \033[0;37m○\033[0m $desc" ;;
    esac
  done
  echo
}

execute_module() {
  local module="$1"
  local module_script="${module}.sh"
  local module_name="${MODULE_NAMES[$module]}"
  
  log "Executing: $module_name"
  set_module_status "$module" "in-progress"
  
  if [[ -f "$MODULES_DIR/$module_script" ]]; then
    if bash "$MODULES_DIR/$module_script"; then
      set_module_status "$module" "completed"
      log "Module $module completed successfully."
      return 0
    else
      set_module_status "$module" "failed"
      err "Module $module failed!"
      return 1
    fi
  else
    log "Local module not found. Fetching from GitHub..."
    if curl -fsSL "${BASE_URL}/${module_script}" | bash; then
      set_module_status "$module" "completed"
      log "Module $module completed successfully."
      return 0
    else
      set_module_status "$module" "failed"
      err "Module $module failed!"
      return 1
    fi
  fi
}

ask_continue_or_restart() {
  echo
  warn "A previous installation is in progress."
  show_progress
  echo
  info "What would you like to do?"
  echo "  1) Continue from where it left off"
  echo "  2) Start a new installation (reset progress)"
  echo "  3) Exit"
  echo
  
  while true; do
    read -rp "Enter your choice [1-3]: " choice
    case "$choice" in
      1) return 0 ;;
      2) warn "Resetting installation progress..."
         rm -f "$PROGRESS_FILE"
         init_progress
         return 0 ;;
      3) info "Installation cancelled."
         exit 0 ;;
      *) warn "Invalid choice. Please enter 1, 2, or 3." ;;
    esac
  done
}

ask_redo_options() {
  echo
  info "Installation is already complete!"
  show_progress
  echo
  info "What would you like to do?"
  echo "  1) Redo specific module"
  echo "  2) Redo entire installation"
  echo "  3) Exit"
  echo
  
  while true; do
    read -rp "Enter your choice [1-3]: " choice
    case "$choice" in
      1) select_module_to_redo
         return ;;
      2) warn "Resetting entire installation..."
         rm -f "$PROGRESS_FILE"
         init_progress
         run_installation
         return ;;
      3) info "Exiting."
         exit 0 ;;
      *) warn "Invalid choice. Please enter 1, 2, or 3." ;;
    esac
  done
}

select_module_to_redo() {
  echo
  info "Select a module to redo:"
  echo
  
  local i=1
  for module in "${MODULES[@]}"; do
    echo "  $i) ${MODULE_NAMES[$module]}"
    ((i++))
  done
  echo "  $i) Back to main menu"
  echo
  
  while true; do
    read -rp "Enter your choice [1-$i]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$i" ]; then
      if [ "$choice" -eq "$i" ]; then
        ask_redo_options
        return
      fi
      
      local selected_module="${MODULES[$((choice-1))]}"
      log "Re-executing: ${MODULE_NAMES[$selected_module]}"
      set_module_status "$selected_module" "not-started"
      execute_module "$selected_module"
      
      echo
      info "Module re-execution complete."
      read -rp "Press Enter to return to menu..." dummy
      ask_redo_options
      return
    else
      warn "Invalid choice. Please enter a number between 1 and $i."
    fi
  done
}

run_installation() {
  log "Starting installation process..."
  echo
  
  local failed=false
  
  for module in "${MODULES[@]}"; do
    local status=$(get_module_status "$module")
    
    if [[ "$status" == "completed" ]]; then
      info "Skipping ${MODULE_NAMES[$module]} (already completed)"
      continue
    fi
    
    echo
    log "========================================" 
    log "Starting: ${MODULE_NAMES[$module]}"
    log "========================================"
    echo
    
    if ! execute_module "$module"; then
      failed=true
      err "Installation failed at module: $module"
      echo
      warn "You can re-run this script to continue from this point."
      break
    fi
  done
  
  if [[ "$failed" == "false" ]]; then
    mark_installation_complete
    echo
    log "========================================"
    log "Installation Complete!"
    log "========================================"
    echo
    info "All modules have been installed successfully."
    show_progress
  fi
}

show_banner() {
  cat <<'BANNER'
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║        HOST-SWARM INFRASTRUCTURE INSTALLER                 ║
║                                                            ║
║  Automated Docker Swarm infrastructure deployment          ║
║  with Traefik, Portainer, and optional services            ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
BANNER
  echo
}

main() {
  require_root
  show_banner
  init_progress
  
  local completed=$(is_installation_complete)
  
  if [[ "$completed" == "true" ]]; then
    ask_redo_options
  else
    local pending=$(get_pending_modules)
    if [[ -n "$pending" ]] && [[ -f "$PROGRESS_FILE" ]]; then
      ask_continue_or_restart
    fi
    run_installation
  fi
  
  echo
  log "Thank you for using Host-Swarm Installer!"
  echo
}

trap 'echo; warn "Installation interrupted. Run this script again to continue."; exit 1' INT TERM

main "$@"

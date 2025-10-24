#!/usr/bin/env bash
set -euo pipefail

# =========================
# Module 02: Docker Swarm Setup
# =========================

log() { echo -e "\033[1;32m[+] $*\033[0m"; }
err() { echo -e "\033[1;31m[✗] $*\033[0m"; }
info() { echo -e "\033[1;34m[i] $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }

prompt_default() {
  local prompt="$1"; local default="$2"; local var
  read -rp "$prompt [$default]: " var || true
  echo "${var:-$default}"
}

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

check_swarm_status() {
  local swarm_state
  swarm_state=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "inactive")
  echo "$swarm_state"
}

initiate_new_swarm() {
  log "Initiating new Docker Swarm..."
  echo
  
  # Get advertise address
  local addr_guess
  addr_guess=$(hostname -I 2>/dev/null | awk '{print $1}')
  local ip
  ip=$(prompt_default "Enter advertise IP for Swarm" "${addr_guess:-127.0.0.1}")
  
  log "Initializing Swarm with advertise address: $ip"
  docker swarm init --advertise-addr "$ip"
  
  log "Swarm initialized successfully!"
  echo
  info "To add worker nodes to this swarm, run the following command on the worker node:"
  docker swarm join-token worker | grep "docker swarm join"
  echo
}

connect_to_existing_swarm() {
  log "Connecting to existing Docker Swarm..."
  echo
  
  warn "You need the join token and manager IP from the existing swarm."
  warn "On the manager node, run: docker swarm join-token worker"
  echo
  
  local join_token
  join_token=$(prompt_required "Enter swarm join token")
  
  local manager_ip
  manager_ip=$(prompt_required "Enter manager IP address (with port, e.g., 192.168.1.100:2377)")
  
  log "Joining swarm at $manager_ip..."
  docker swarm join --token "$join_token" "$manager_ip"
  
  log "Successfully joined the swarm!"
}

setup_swarm() {
  local swarm_state
  swarm_state=$(check_swarm_status)
  
  if [[ "$swarm_state" == "active" ]]; then
    log "Docker Swarm is already active on this node."
    docker node ls 2>/dev/null || info "This node is a worker node in the swarm."
    return
  fi
  
  echo "========================================"
  echo "Docker Swarm Setup"
  echo "========================================"
  echo
  info "Do you want to:"
  echo "  1) Initiate a new swarm (this will be the manager node)"
  echo "  2) Connect to an existing swarm (this will be a worker node)"
  echo
  
  local choice
  while true; do
    read -rp "Enter your choice [1-2]: " choice
    case "$choice" in
      1)
        initiate_new_swarm
        break
        ;;
      2)
        connect_to_existing_swarm
        break
        ;;
      *)
        warn "Invalid choice. Please enter 1 or 2."
        ;;
    esac
  done
}

main() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "This module must be run as root (use sudo)."
    exit 1
  fi
  
  echo "========================================"
  echo "Module 02: Docker Swarm Setup"
  echo "========================================"
  echo
  
  setup_swarm
  
  log "Module 02 completed successfully."
}

main "$@"

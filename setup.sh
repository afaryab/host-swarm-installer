#!/usr/bin/env bash
set -euo pipefail

# =========================
# create_dirs() {
  BASE="/mnt/hosting/infrastructure"
  mkdir -p "$BASE/traefik/letsencrypt" \
           "$BASE/portainer/data" \
           "$BASE/shared" \
           "$BASE/metrics"
  chmod 600 "$BASE/traefik/letsencrypt" || true
  touch "$BASE/traefik/letsencrypt/acme.json"
  chmod 600 "$BASE/traefik/letsencrypt/acme.json"
}Infrastructure
# =========================
# This script installs Docker + Swarm, prepares /mnt/hosting/infrastructure,
# asks for domains & ACME email, then deploys a single Swarm stack: "infrastructure".
# Services: traefik, portainer.
# It also sets up day-wise usage JSON exports for future billing.
# No Docker named volumes are used; everything is mounted from local folders.

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run as root (sudo)." >&2
    exit 1
  fi
}

log() { echo -e "\033[1;32m[+] $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }
err() { echo -e "\033[1;31m[✗] $*\033[0m"; }

prompt_default() {
  local prompt="$1"; local default="$2"; local var
  read -rp "$prompt [$default]: " var || true
  echo "${var:-$default}"
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker already installed."
    return
  fi
  log "Installing Docker Engine..."
  if [[ -e /etc/debian_version ]]; then
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") \
      $(. /etc/os-release; echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin jq
    systemctl enable --now docker
  else
    err "This installer currently supports Debian/Ubuntu. Please install Docker manually."
    exit 1
  fi
}

ensure_swarm() {
  if docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -qi 'active'; then
    log "Docker Swarm already initialized."
  else
    # figure out advertise address (best effort)
    local ip addr_guess
    addr_guess=$(hostname -I 2>/dev/null | awk '{print $1}')
    ip=$(prompt_default "Advertise IP for Swarm" "${addr_guess:-127.0.0.1}")
    log "Initializing Swarm..."
    docker swarm init --advertise-addr "$ip" || true
  fi
}

create_dirs() {
  BASE="/mnt/hosting/infrastructure"
  mkdir -p 
    "$BASE/traefik/letsencrypt" 
    "$BASE/portainer/data" 
    "$BASE/shared" 
    "$BASE/metrics"
  chmod 600 "$BASE/traefik/letsencrypt" || true
  touch "$BASE/traefik/letsencrypt/acme.json"
  chmod 600 "$BASE/traefik/letsencrypt/acme.json"
}

create_networks() {
  docker network create --driver overlay traefik-net >/dev/null 2>&1 || true
  docker network create --driver overlay infra-net >/dev/null 2>&1 || true
}

write_env_and_stack() {
  local BASE="/mnt/hosting/infrastructure"
  local ACME_EMAIL="$1"
  local TRAEFIK_HOST="$2"
  local PORTAINER_HOST="$3"
  local WANT_LOCAL_SERVER_MANAGER="$4"
  local REMOTE_SERVER_MANAGER_URL="$5"
  local REMOTE_SERVER_MANAGER_SECRET="$6"

  # Generate docker-compose.yml with inlined values (no .env file)
  cat > "$BASE/docker-compose.yml" <<STACK
version: "3.9"

networks:
  traefik-net:
    external: true
  infra-net:
    external: true

services:

  # ----------------
  # Traefik (edge)
  # ----------------
  traefik:
    image: traefik:v3.4
    command:
      - --providers.swarm=true
      - --providers.swarm.network=traefik-net
      - --providers.swarm.exposedByDefault=false
      - --providers.file.directory=/dynamic
      - --providers.file.watch=true
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --entrypoints.traefik.address=:8080
      - --api.dashboard=true
      - --certificatesresolvers.le.acme.httpchallenge.entrypoint=web
      - --certificatesresolvers.le.acme.email=${ACME_EMAIL}
      - --certificatesresolvers.le.acme.storage=/letsencrypt/acme.json
      - --log.level=INFO
      - --accesslog=true
    ports:
      - target: 80
        published: 80
        protocol: tcp
        mode: host
      - target: 443
        published: 443
        protocol: tcp
        mode: host
      - target: 8080
        published: 8080
        protocol: tcp
        mode: host
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /mnt/hosting/infrastructure/traefik/letsencrypt:/letsencrypt
      - /mnt/hosting/infrastructure/traefik/dynamic:/dynamic
    networks:
      - traefik-net
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [node.role == manager]
      labels:
        - "traefik.enable=true"
        - "traefik.swarm.network=traefik-net"
        - "traefik.http.routers.traefik.rule=Host(\`${TRAEFIK_HOST}\`)"
        - "traefik.http.routers.traefik.entrypoints=websecure"
        - "traefik.http.routers.traefik.service=api@internal"
        - "traefik.http.routers.traefik.tls=true"
        - "traefik.http.routers.traefik.tls.certresolver=le"
        - "traefik.http.services.traefik.loadbalancer.server.port=8080"
        - "traefik.http.routers.http-catchall.rule=HostRegexp(\`{host:.+}\`)"
        - "traefik.http.routers.http-catchall.entrypoints=web"
        - "traefik.http.routers.http-catchall.middlewares=redirect-to-https"
        - "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https"

  # ----------------
  # Portainer
  # ----------------
  portainer:
    image: portainer/portainer-ce:latest
    environment:
      - EDGE_INACTIVITY_TIMEOUT=0
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /mnt/hosting/infrastructure/portainer/data:/data
    networks:
      - traefik-net
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [node.role == manager]
      labels:
        - "traefik.enable=true"
        - "traefik.swarm.network=traefik-net"
        - "traefik.http.middlewares.port-redirect.redirectscheme.scheme=https"
        - "traefik.http.middlewares.port-redirect.redirectscheme.permanent=true"
        - "traefik.http.routers.port.rule=Host(\`${PORTAINER_HOST}\`)"
        - "traefik.http.routers.port.entrypoints=websecure"
        - "traefik.http.routers.port.tls=true"
        - "traefik.http.routers.port.tls.certresolver=le"
        - "traefik.http.services.port.loadbalancer.server.port=9000"
        - "traefik.http.routers.port-http.rule=Host(\`${PORTAINER_HOST}\`)"
        - "traefik.http.routers.port-http.entrypoints=web"
        - "traefik.http.routers.port-http.middlewares=port-redirect"

  # ----------------
  # Placeholders (commented out for now)
  # ----------------

  # server_manager:
  #   image: yourorg/server_manager:stable
  #   environment:
  #     BASE_URL: https://${REMOTE_SERVER_MANAGER_URL}
  #     AUTH_SECRET: ${REMOTE_SERVER_MANAGER_SECRET}
  #   networks:
  #     - infra-net
  #     - traefik-net
  #   deploy:
  #     replicas: 1
  #     placement:
  #       constraints: [node.role == manager]
  #   labels:
  #     - "traefik.enable=false"

  # swarm-connect:
  #   image: yourorg/swarm-connect:stable
  #   environment:
  #     MANAGER_URL: https://${REMOTE_SERVER_MANAGER_URL}
  #     AUTH_SECRET: ${REMOTE_SERVER_MANAGER_SECRET}
  #   networks:
  #     - infra-net
  #   deploy:
  #     replicas: 1
  #     placement:
  #       constraints: [node.role == manager]
STACK
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

  echo
  echo "=== Server Manager placeholders ==="
  echo "Do you want to create a placeholder service here, or reference an existing remote one?"
  echo "  1) Create local placeholder (commented, ready to enable)"
  echo "  2) Use existing remote (commented, store URL/secret placeholders)"
  CHOICE=$(prompt_default "Choose 1 or 2" "1")
  REMOTE_URL=""; REMOTE_SECRET=""
  if [[ "$CHOICE" == "2" ]]; then
    REMOTE_URL=$(prompt_default "Remote server_manager URL" "https://manager.${PRIMARY_DOMAIN}")
    REMOTE_SECRET=$(prompt_default "Remote server_manager secret" "$(openssl rand -hex 16)")
  fi

  write_env_and_stack "$ACME_EMAIL" "$TRAEFIK_HOST" "$PORTAINER_HOST" "$CHOICE" "$REMOTE_URL" "$REMOTE_SECRET"

  deploy_stack
  setup_metrics_timer

  echo
  log "All set! Services are now available:"
  log "Traefik:     https://${TRAEFIK_HOST}"
  log "Portainer:   https://${PORTAINER_HOST}"
  echo
  warn "Remember to point service domains to this host (A/AAAA records) in your DNS provider."
  warn "Primary domain: ${PRIMARY_DOMAIN}"
}

main "$@"

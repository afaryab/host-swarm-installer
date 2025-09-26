#!/usr/bin/env bash
set -euo pipefail

# =========================
# Host-Swarm Infrastructure
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
  local swarm_state
  swarm_state=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null)
  if [[ "$swarm_state" == "active" ]]; then
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
  mkdir -p "$BASE/traefik/letsencrypt" \
           "$BASE/traefik/dynamic" \
           "$BASE/traefik/dynamic/certs" \
           "$BASE/portainer/data" \
           "$BASE/keycloak/data" \
           "$BASE/keycloak/postgres" \
           "$BASE/server-manager/app" \
           "$BASE/server-manager/mysql" \
           "$BASE/shared" \
           "$BASE/metrics"
  chmod 600 "$BASE/traefik/letsencrypt" || true
  touch "$BASE/traefik/letsencrypt/acme.json"
  chmod 600 "$BASE/traefik/letsencrypt/acme.json"
}

create_networks() {
  docker network create --driver overlay traefik-net >/dev/null 2>&1 || true
}

write_env_and_stack() {
  local BASE="/mnt/hosting/infrastructure"
  local ACME_EMAIL="$1"
  local TRAEFIK_HOST="$2"
  local PORTAINER_HOST="$3"
  local WANT_LOCAL_SERVER_MANAGER="$4"
  local SERVER_MANAGER_DOMAIN="$5"
  local CF_DNS_API_TOKEN="$6"
  local KEYCLOAK_HOST="$7"
  local CF_ORIGIN_KEY="$8"
  local CF_ORIGIN_PEM="$9"
  local KC_USER="${10}"
  local KC_PASS="${11}"

  cat > "$BASE/traefik/dynamic/certs/cf-origin.pem" <<EOF
$CF_ORIGIN_PEM
EOF
  chmod 644 "$BASE/traefik/dynamic/certs/cf-origin.pem"

  cat > "$BASE/traefik/dynamic/certs/cf-origin.key" <<EOF
$CF_ORIGIN_KEY
EOF
  chmod 600 "$BASE/traefik/dynamic/certs/cf-origin.key"

  cat > "$BASE/traefik/dynamic/tls.yml" <<EOF
tls:
  certificates:
    - certFile: /dynamic/certs/cf-origin.pem
      keyFile: /dynamic/certs/cf-origin.key
EOF

  # Generate docker-compose.yml with inlined values (no .env file)
  cat > "$BASE/docker-compose.yml" <<STACK
version: "3.9"

networks:
  traefik-net:
    external: true
  keycloak-net:
    driver: overlay
  server-manager-net:
    driver: overlay

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
      # - --certificatesresolvers.le.acme.httpchallenge.entrypoint=web
      - --certificatesresolvers.le.acme.email=${ACME_EMAIL}
      - --certificatesresolvers.le.acme.storage=/letsencrypt/acme.json
      - --certificatesresolvers.le.acme.dnschallenge.provider=cloudflare
      - --certificatesresolvers.le.acme.dnschallenge.delaybeforecheck=0
      - --serversTransport.insecureSkipVerify=false
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
    environment:
      - CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN}
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
        # - "traefik.http.routers.traefik.tls.certresolver=le"
        - "traefik.http.services.traefik.loadbalancer.server.port=8080"
        # - "traefik.http.routers.http-catchall.rule=HostRegexp(\`{host:.+}\`)"
        # - "traefik.http.routers.http-catchall.entrypoints=web"
        # - "traefik.http.routers.http-catchall.middlewares=redirect-to-https"
        - "traefik.http.routers.traefik-http.rule=Host(\`${TRAEFIK_HOST}\`)"
        - "traefik.http.routers.traefik-http.entrypoints=web"
        - "traefik.http.routers.traefik-http.middlewares=redirect-to-https"
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
        # - "traefik.http.routers.port.tls.certresolver=le"
        - "traefik.http.services.port.loadbalancer.server.port=9000"
        - "traefik.http.routers.port-http.rule=Host(\`${PORTAINER_HOST}\`)"
        - "traefik.http.routers.port-http.entrypoints=web"
        - "traefik.http.routers.port-http.middlewares=port-redirect"

STACK

  # Add Keycloak services only if server manager is wanted
  if [[ "$WANT_LOCAL_SERVER_MANAGER" == "yes" ]]; then
    cat >> "$BASE/docker-compose.yml" <<KEYCLOAK_STACK

  # ----------------
  # Keycloak + Postgres
  # ----------------
  keycloak:
    image: quay.io/keycloak/keycloak:latest
    environment:
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://keycloak-db:5432/keycloak
      KC_DB_USERNAME: keycloak
      KC_DB_PASSWORD: keycloak
      KC_HOSTNAME: ${KEYCLOAK_HOST}
      KC_HTTP_ENABLED: "true"
      KC_METRICS_ENABLED: "true"
      KC_PROXY_HEADERS: xforwarded
      KC_BOOTSTRAP_ADMIN_USERNAME: ${KC_USER}
      KC_BOOTSTRAP_ADMIN_PASSWORD: ${KC_PASS}
    command: ["start"]
    volumes:
      - /mnt/hosting/infrastructure/keycloak/data:/opt/keycloak/data
    depends_on:
      - keycloak-db
    networks:
      - keycloak-net
      - traefik-net
    deploy:
      replicas: 1
      placement:
        constraints: [node.role == manager]
      resources:
        limits:
          cpus: "1"
          memory: 1024M
        reservations:
          cpus: "0.25"
          memory: 128M
      labels:
        - "traefik.enable=true"
        - "traefik.swarm.network=traefik-net"
        - "traefik.http.middlewares.kc-redirect.redirectscheme.scheme=https"
        - "traefik.http.middlewares.kc-redirect.redirectscheme.permanent=true"
        - "traefik.http.routers.kc.rule=Host(\`${KEYCLOAK_HOST}\`)"
        - "traefik.http.routers.kc.entrypoints=websecure"
        - "traefik.http.routers.kc.tls=true"
        - "traefik.http.routers.kc.tls.certresolver=le"
        - "traefik.http.services.kc.loadbalancer.server.port=8080"
        - "traefik.http.routers.kc-http.rule=Host(\`${KEYCLOAK_HOST}\`)"
        - "traefik.http.routers.kc-http.entrypoints=web"
        - "traefik.http.routers.kc-http.middlewares=kc-redirect"

  keycloak-db:
    image: postgres:15
    environment:
      POSTGRES_DB: keycloak
      POSTGRES_USER: keycloak
      POSTGRES_PASSWORD: keycloak
    volumes:
      - /mnt/hosting/infrastructure/keycloak/postgres:/var/lib/postgresql/data
    networks:
      - keycloak-net
    deploy:
      placement:
        constraints: [node.role == manager]

  # ----------------
  # Server Manager + Mysql
  # ----------------
  server-manager:
    image: ahmadfaryabkokab/host-swarm:0.0.6
    environment:
      APP_NAME:Host-Swarm
      APP_ENV:production
      APP_DEBUG:false
      APP_URL:https://${SERVER_MANAGER_DOMAIN}
      DB_CONNECTION:mysql
      DB_HOST:server-manager-mysql
      DB_PORT:3306
      DB_DATABASE:hostswarm
      DB_USERNAME:hostswarm
      DB_PASSWORD:hostswarmpassword
      BROADCAST_DRIVER:pusher
      BROADCAST_CONNECTION:pusher
      QUEUE_CONNECTION:database
      CACHE_STORE:database
      REDIS_CLIENT:phpredis
      REDIS_HOST:server-manager-redis
      REDIS_PASSWORD:null
      REDIS_PORT:6379
      MAIL_MAILER:smtp
      MAIL_HOST:smtp.mailtrap.io
      MAIL_PORT:2525
      MAIL_USERNAME:null
      MAIL_PASSWORD:null
      MAIL_ENCRYPTION:null
      MAIL_FROM_ADDRESS:admin@${SERVER_MANAGER_DOMAIN}
      MAIL_FROM_NAME:"Host Swarm"
      GITHUB_CLIENT_ID:null
      GITHUB_CLIENT_SECRET:null
      GOOGLE_CLIENT_ID:null
      GOOGLE_CLIENT_SECRET:null
      GITLAB_CLIENT_ID:null
      GITLAB_CLIENT_SECRET:null
      PADDLE_CLIENT_SIDE_TOKEN:null
      PADDLE_API_KEY:your-paddle-api-key
      PADDLE_RETAIN_KEYS:your-paddle-retain-key
      PADDLE_WEBHOOK_SECRET:your-paddle-webhook-secret
      PADDLE_SANDBOX:true
      CLOUDFLARE_EMAIL:null
      CLOUDFLARE_API_KEY:null
      CLOUDFLARE_ZONE_ID:null
      CLOUDFLARE_TARGET_IP:null
      STRIPE_KEY:null
      STRIPE_SECRET:null
      STRIPE_WEBHOOK_SECRET:null
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
  echo "Paste Cloudflare Origin CA key (PEM format), then Ctrl-D:"
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

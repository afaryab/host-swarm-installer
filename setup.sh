#!/usr/bin/env bash
set -euo pipefail

# =========================
# Host-Swarm Infrastructure
# =========================
# This script installs Docker + Swarm, prepares /mnt/hosting/infrastructure,
# asks for domains & ACME email, then deploys a single Swarm stack: "infrastructure".
# Services: traefik, portainer, keycloak(+pg), n8n(+pg), dns(powerdns + mariadb), dns-admin.
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
  mkdir -p \
    "$BASE/traefik/letsencrypt" \
    "$BASE/portainer/data" \
    "$BASE/keycloak/data" "$BASE/keycloak/postgres" \
    "$BASE/n8n/data" "$BASE/n8n/postgres" \
    "$BASE/dns/conf.d" "$BASE/dns/zones" "$BASE/dns/db" \
    "$BASE/dns-admin/uploads" "$BASE/dns-admin/secrets" \
    "$BASE/shared" \
    "$BASE/metrics"
  chmod 600 "$BASE/traefik/letsencrypt" || true
  touch "$BASE/traefik/letsencrypt/acme.json"
  chmod 600 "$BASE/traefik/letsencrypt/acme.json"

  # Default PDNS config (minimal authoritative + gmysql)
  if [[ ! -f "$BASE/dns/conf.d/pdns.conf" ]]; then
    cat > "$BASE/dns/conf.d/pdns.conf" <<'EOF'
launch=gmysql
gmysql-host=dns-db
gmysql-user=pdns
gmysql-password=pdns-pass
gmysql-dbname=pdns
api=yes
api-key=changeme-api-key
webserver=yes
webserver-address=0.0.0.0
webserver-port=8081
EOF
  fi
}

create_networks() {
  docker network create --driver overlay traefik-net >/dev/null 2>&1 || true
  docker network create --driver overlay infra-net >/dev/null 2>&1 || true
}

write_env_and_stack() {
  local BASE="/mnt/hosting/infrastructure"
  local DNS_ROOT="$1"
  local ACME_EMAIL="$2"
  local TRAEFIK_HOST="$3"
  local PORTAINER_HOST="$4"
  local KEYCLOAK_HOST="$5"
  local N8N_HOST="$6"
  local PDNS_ADMIN_HOST="$7"
  local WANT_LOCAL_SERVER_MANAGER="$8"
  local REMOTE_SERVER_MANAGER_URL="$9"
  local REMOTE_SERVER_MANAGER_SECRET="${10}"

  # Generate secrets first (shell-time, NOT compose-time)
  local KC_DB="processton-keycloak"
  local KC_DB_USER="processtonkeycloak"
  local KC_DB_PASS=$(openssl rand -hex 12)
  local KC_BOOTSTRAP_ADMIN_PASSWORD=$(openssl rand -hex 8)

  local N8N_DB="n8n"
  local N8N_DB_USER="n8n"
  local N8N_DB_PASS=$(openssl rand -hex 12)
  local N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)

  local PDNS_DB="pdns"
  local PDNS_DB_USER="pdns"
  local PDNS_DB_PASS=$(openssl rand -hex 12)
  local PDNS_API_KEY=$(openssl rand -hex 16)
  local PDA_SECRET_KEY=$(openssl rand -hex 24)

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
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --entrypoints.traefik.address=:8080
      - --api.dashboard=true
      - --certificatesresolvers.le.acme.httpchallenge.entrypoint=web
      - --certificatesresolvers.le.acme.email=${ACME_EMAIL}
      - --certificatesresolvers.le.acme.storage=/letsencrypt/acme.json
      - --log.level=INFO
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
    networks:
      - traefik-net
    deploy:
      mode: global
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
    ports:
      - "9000:9000"
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
  # Keycloak + Postgres
  # ----------------
  keycloak:
    image: quay.io/keycloak/keycloak:latest
    environment:
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://keycloak-db:5432/${KC_DB}
      KC_DB_USERNAME: ${KC_DB_USER}
      KC_DB_PASSWORD: ${KC_DB_PASS}
      KC_HOSTNAME: ${KEYCLOAK_HOST}
      KC_HTTP_ENABLED: "true"
      KC_METRICS_ENABLED: "true"
      KC_PROXY_HEADERS: xforwarded
      KC_BOOTSTRAP_ADMIN_USERNAME: admin
      KC_BOOTSTRAP_ADMIN_PASSWORD: ${KC_BOOTSTRAP_ADMIN_PASSWORD}
    command: ["start"]
    volumes:
      - /mnt/hosting/infrastructure/keycloak/data:/opt/keycloak/data
    depends_on:
      - keycloak-db
    networks:
      - infra-net
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
      POSTGRES_DB: ${KC_DB}
      POSTGRES_USER: ${KC_DB_USER}
      POSTGRES_PASSWORD: ${KC_DB_PASS}
    volumes:
      - /mnt/hosting/infrastructure/keycloak/postgres:/var/lib/postgresql/data
    networks:
      - infra-net
    deploy:
      placement:
        constraints: [node.role == manager]

  # ----------------
  # n8n + Postgres
  # ----------------
  n8n:
    image: n8nio/n8n:latest
    environment:
      N8N_HOST: ${N8N_HOST}
      N8N_PORT: 5678
      WEBHOOK_URL: https://${N8N_HOST}/
      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: n8n-db
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: ${N8N_DB}
      DB_POSTGRESDB_USER: ${N8N_DB_USER}
      DB_POSTGRESDB_PASSWORD: ${N8N_DB_PASS}
      EXECUTIONS_MODE: regular
      GENERIC_TIMEZONE: Asia/Karachi
    volumes:
      - /mnt/hosting/infrastructure/n8n/data:/home/node/.n8n
    depends_on:
      - n8n-db
    networks:
      - infra-net
      - traefik-net
    deploy:
      replicas: 1
      placement:
        constraints: [node.role == manager]
      labels:
        - "traefik.enable=true"
        - "traefik.swarm.network=traefik-net"
        - "traefik.http.routers.n8n.rule=Host(\`${N8N_HOST}\`)"
        - "traefik.http.routers.n8n.entrypoints=websecure"
        - "traefik.http.routers.n8n.tls=true"
        - "traefik.http.routers.n8n.tls.certresolver=le"
        - "traefik.http.services.n8n.loadbalancer.server.port=5678"

  n8n-db:
    image: postgres:15
    environment:
      POSTGRES_DB: ${N8N_DB}
      POSTGRES_USER: ${N8N_DB_USER}
      POSTGRES_PASSWORD: ${N8N_DB_PASS}
    volumes:
      - /mnt/hosting/infrastructure/n8n/postgres:/var/lib/postgresql/data
    networks:
      - infra-net
    deploy:
      placement:
        constraints: [node.role == manager]

  # ----------------
  # PowerDNS (authoritative) + MariaDB
  # ----------------
  dns-db:
    image: mariadb:10.11
    environment:
      MYSQL_DATABASE: ${PDNS_DB}
      MYSQL_USER: ${PDNS_DB_USER}
      MYSQL_PASSWORD: ${PDNS_DB_PASS}
      MYSQL_ROOT_PASSWORD: ${PDNS_DB_PASS}
    volumes:
      - /mnt/hosting/infrastructure/dns/db:/var/lib/mysql
    networks:
      - infra-net
    deploy:
      placement:
        constraints: [node.role == manager]

    dns:
    image: powerdns/pdns-auth-46:latest
    environment:
      PDNS_gmysql_host: dns-db
      PDNS_gmysql_user: ${PDNS_DB_USER}
      PDNS_gmysql_password: ${PDNS_DB_PASS}
      PDNS_gmysql_dbname: ${PDNS_DB}
      PDNS_api: "yes"
      PDNS_api_key: ${PDNS_API_KEY}
      PDNS_webserver: "yes"
      PDNS_webserver_address: 0.0.0.0
      PDNS_webserver_port: 8081
    ports:
      - target: 53
        published: 53
        protocol: tcp
        mode: host
      - target: 53
        published: 53
        protocol: udp
        mode: host
    volumes:
      # keep zones mount only (optional)
      - /mnt/hosting/infrastructure/dns/zones:/zones
    networks:
      - infra-net
      - traefik-net
    deploy:
      replicas: 1
      placement:
        constraints: [node.role == manager]
      labels:
        - "traefik.enable=false"


  # ----------------
  # PowerDNS-Admin (UI) 
  # ----------------
  dns-admin:
    image: ngoduykhanh/powerdns-admin:latest
    environment:
      SQLALCHEMY_DATABASE_URI: mysql+pymysql://${PDNS_DB_USER}:${PDNS_DB_PASS}@dns-db/${PDNS_DB}
      PDNS_API_URL: http://dns:8081
      PDNS_API_KEY: ${PDNS_API_KEY}
      GUNICORN_TIMEOUT: 300
      SECRET_KEY: ${PDA_SECRET_KEY}
    depends_on:
      - dns
      - dns-db
    volumes:
      - /mnt/hosting/infrastructure/dns-admin/uploads:/uploads
      - /mnt/hosting/infrastructure/dns-admin/secrets:/secrets
    networks:
      - infra-net
      - traefik-net
    deploy:
      replicas: 1
      placement:
        constraints: [node.role == manager]
      labels:
        - "traefik.enable=true"
        - "traefik.swarm.network=traefik-net"
        - "traefik.http.routers.pda.rule=Host(\`${PDNS_ADMIN_HOST}\`)"
        - "traefik.http.routers.pda.entrypoints=websecure"
        - "traefik.http.routers.pda.tls=true"
        - "traefik.http.routers.pda.tls.certresolver=le"
        - "traefik.http.services.pda.loadbalancer.server.port=80"

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
    read -rp "Do you want to clear the previous installation and redeploy? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      log "Stopping and removing existing stack..."
      docker stack rm infrastructure || true
      sleep 5
      log "Removing old files..."
      rm -rf "$BASE"/*
      log "Old installation cleared."
    else
      err "Aborting installation."
      exit 1
    fi
  fi

  create_dirs
  create_networks

  echo
  echo "=== Domain & ACME configuration ==="
  DNS_ROOT=$(prompt_default "Primary DNS server domain (authoritative; used for defaults)" "dns.example.com")
  ACME_EMAIL=$(prompt_default "Email for Let's Encrypt/ACME" "admin@${DNS_ROOT}")

  # sensible service defaults under the same DNS root
  TRAEFIK_HOST=$(prompt_default "Traefik dashboard domain" "traefik.${DNS_ROOT}")
  PORTAINER_HOST=$(prompt_default "Portainer domain" "port.${DNS_ROOT}")
  KEYCLOAK_HOST=$(prompt_default "Keycloak domain" "employee-id.${DNS_ROOT}")
  N8N_HOST=$(prompt_default "n8n domain" "n8n.${DNS_ROOT}")
  PDNS_ADMIN_HOST=$(prompt_default "PowerDNS-Admin domain" "dns-admin.${DNS_ROOT}")

  echo
  echo "=== Server Manager placeholders ==="
  echo "Do you want to create a placeholder service here, or reference an existing remote one?"
  echo "  1) Create local placeholder (commented, ready to enable)"
  echo "  2) Use existing remote (commented, store URL/secret placeholders)"
  CHOICE=$(prompt_default "Choose 1 or 2" "1")
  REMOTE_URL=""; REMOTE_SECRET=""
  if [[ "$CHOICE" == "2" ]]; then
    REMOTE_URL=$(prompt_default "Remote server_manager URL" "https://manager.${DNS_ROOT}")
    REMOTE_SECRET=$(prompt_default "Remote server_manager secret" "$(openssl rand -hex 16)")
  fi

  write_env_and_stack "$DNS_ROOT" "$ACME_EMAIL" "$TRAEFIK_HOST" "$PORTAINER_HOST" "$KEYCLOAK_HOST" "$N8N_HOST" "$PDNS_ADMIN_HOST" "$CHOICE" "$REMOTE_URL" "$REMOTE_SECRET"

  deploy_stack
  setup_metrics_timer

  echo
  log "All set! Verify DNS -> CNAMEs to ${DNS_ROOT} as needed."
  log "Traefik:     https://${TRAEFIK_HOST}"
  log "Portainer:   https://${PORTAINER_HOST}"
  log "Keycloak:    https://${KEYCLOAK_HOST}"
  log "n8n:         https://${N8N_HOST}"
  log "DNS-Admin:   https://${PDNS_ADMIN_HOST}"
  echo
  warn "Remember to point service domains to this host (A/AAAA) or via CNAME to ${DNS_ROOT} (per your plan)."
}

main "$@"

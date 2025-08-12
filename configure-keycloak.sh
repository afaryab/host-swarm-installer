#!/usr/bin/env bash
set -euo pipefail

# =========================
# Keycloak Configuration Script
# =========================
# This script configures Keycloak with the infrastructure services.
# It creates an admin user, sets up a realm, and configures OIDC clients
# for Traefik, Portainer, and PowerDNS Admin integration.

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

prompt_password() {
  local prompt="$1"
  local password
  echo -n "$prompt: "
  read -s password
  echo
  echo "$password"
}

wait_for_keycloak() {
  local keycloak_url="$1"
  log "Waiting for Keycloak to be ready at $keycloak_url..."
  
  for i in {1..60}; do
    if curl -s -f "$keycloak_url/health/ready" >/dev/null 2>&1; then
      log "Keycloak is ready!"
      return 0
    fi
    echo -n "."
    sleep 5
  done
  
  err "Keycloak failed to become ready within 5 minutes"
  return 1
}

get_admin_token() {
  local keycloak_url="$1"
  local admin_user="$2" 
  local admin_pass="$3"
  
  local token=$(curl -s -X POST "$keycloak_url/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=$admin_user" \
    -d "password=$admin_pass" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" | jq -r '.access_token')
  
  if [[ "$token" == "null" || -z "$token" ]]; then
    err "Failed to get admin token"
    return 1
  fi
  
  echo "$token"
}

create_realm() {
  local keycloak_url="$1"
  local token="$2"
  local realm_name="$3"
  
  log "Creating realm: $realm_name"
  
  local realm_config=$(cat <<EOF
{
  "realm": "$realm_name",
  "enabled": true,
  "displayName": "Infrastructure Services",
  "registrationAllowed": false,
  "registrationEmailAsUsername": true,
  "rememberMe": true,
  "verifyEmail": true,
  "loginWithEmailAllowed": true,
  "duplicateEmailsAllowed": false,
  "resetPasswordAllowed": true,
  "editUsernameAllowed": false,
  "bruteForceProtected": true,
  "accessTokenLifespan": 3600,
  "ssoSessionIdleTimeout": 1800,
  "ssoSessionMaxLifespan": 36000
}
EOF
)

  curl -s -X POST "$keycloak_url/admin/realms" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "$realm_config" || {
      warn "Realm might already exist, continuing..."
    }
}

create_user() {
  local keycloak_url="$1"
  local token="$2"
  local realm="$3"
  local email="$4"
  local password="$5"
  local first_name="$6"
  local last_name="$7"
  
  log "Creating user: $email"
  
  local user_config=$(cat <<EOF
{
  "username": "$email",
  "email": "$email",
  "firstName": "$first_name",
  "lastName": "$last_name",
  "enabled": true,
  "emailVerified": true,
  "credentials": [{
    "type": "password",
    "value": "$password",
    "temporary": false
  }],
  "realmRoles": ["admin"]
}
EOF
)

  local user_id=$(curl -s -X POST "$keycloak_url/admin/realms/$realm/users" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "$user_config" -w "%{http_code}" -o /tmp/kc_user_response)
  
  if [[ "$user_id" == "201" ]]; then
    log "User created successfully"
  else
    warn "User might already exist or there was an error"
  fi
}

create_client() {
  local keycloak_url="$1"
  local token="$2"
  local realm="$3"
  local client_id="$4"
  local client_name="$5"
  local redirect_uris="$6"
  local base_url="$7"
  
  log "Creating OIDC client: $client_name"
  
  local client_config=$(cat <<EOF
{
  "clientId": "$client_id",
  "name": "$client_name",
  "description": "OIDC client for $client_name",
  "enabled": true,
  "clientAuthenticatorType": "client-secret",
  "redirectUris": $redirect_uris,
  "webOrigins": ["$base_url"],
  "protocol": "openid-connect",
  "publicClient": false,
  "standardFlowEnabled": true,
  "implicitFlowEnabled": false,
  "directAccessGrantsEnabled": false,
  "serviceAccountsEnabled": false,
  "authorizationServicesEnabled": false,
  "fullScopeAllowed": true,
  "attributes": {
    "saml.assertion.signature": "false",
    "saml.force.post.binding": "false",
    "saml.multivalued.roles": "false",
    "saml.encrypt": "false",
    "oauth2.device.authorization.grant.enabled": "false",
    "backchannel.logout.revoke.offline.tokens": "false",
    "saml.server.signature": "false",
    "saml.server.signature.keyinfo.ext": "false",
    "exclude.session.state.from.auth.response": "false",
    "oidc.ciba.grant.enabled": "false",
    "saml.artifact.binding": "false",
    "backchannel.logout.session.required": "true",
    "client_credentials.use_refresh_token": "false",
    "saml_force_name_id_format": "false",
    "require.pushed.authorization.requests": "false",
    "saml.client.signature": "false",
    "tls.client.certificate.bound.access.tokens": "false",
    "saml.authnstatement": "false",
    "display.on.consent.screen": "false",
    "saml.onetimeuse.condition": "false"
  }
}
EOF
)

  curl -s -X POST "$keycloak_url/admin/realms/$realm/clients" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "$client_config" || {
      warn "Client $client_id might already exist"
    }
}

get_client_secret() {
  local keycloak_url="$1"
  local token="$2"
  local realm="$3"
  local client_id="$4"
  
  # Get client internal ID
  local internal_id=$(curl -s -X GET "$keycloak_url/admin/realms/$realm/clients?clientId=$client_id" \
    -H "Authorization: Bearer $token" | jq -r '.[0].id')
  
  if [[ "$internal_id" == "null" || -z "$internal_id" ]]; then
    err "Failed to get client ID for $client_id"
    return 1
  fi
  
  # Get client secret
  local secret=$(curl -s -X GET "$keycloak_url/admin/realms/$realm/clients/$internal_id/client-secret" \
    -H "Authorization: Bearer $token" | jq -r '.value')
  
  echo "$secret"
}

update_docker_compose_for_auth() {
  local base_dir="/mnt/hosting/infrastructure"
  local compose_file="$base_dir/docker-compose.yml"
  local keycloak_host="$1"
  local realm="$2"
  local traefik_client_secret="$3"
  local portainer_client_secret="$4"
  local pdns_admin_client_secret="$5"
  
  log "Updating docker-compose.yml with Keycloak authentication settings..."
  
  # Backup original file
  cp "$compose_file" "$compose_file.backup.$(date +%s)"
  
  # Create temporary file with authentication settings
  local temp_file="/tmp/docker-compose-auth.yml"
  
  # Note: In a real implementation, you would modify the docker-compose.yml
  # to add authentication environment variables and middleware configurations
  # This is a simplified example showing the structure
  
  cat >> "$compose_file" <<EOF

# Keycloak Authentication Configuration
# Added by configure-keycloak.sh on $(date)
# 
# Authentication settings for infrastructure services:
# - Keycloak Host: $keycloak_host
# - Realm: $realm
# - OIDC Issuer: https://$keycloak_host/realms/$realm
#
# Client Secrets (store securely):
# - Traefik: $traefik_client_secret
# - Portainer: $portainer_client_secret  
# - PowerDNS Admin: $pdns_admin_client_secret
#
# Note: Full OIDC integration requires service-specific configuration
# Please refer to each service's documentation for complete setup.
EOF

  log "Authentication configuration added to docker-compose.yml"
  log "Backup saved as: $compose_file.backup.*"
}

generate_auth_config() {
  local base_dir="/mnt/hosting/infrastructure"
  local keycloak_host="$1"
  local realm="$2"
  local traefik_client_secret="$3"
  local portainer_client_secret="$4"
  local pdns_admin_client_secret="$5"
  
  local config_file="$base_dir/keycloak-auth-config.json"
  
  log "Generating authentication configuration file..."
  
  cat > "$config_file" <<EOF
{
  "keycloak": {
    "host": "$keycloak_host",
    "realm": "$realm",
    "issuer": "https://$keycloak_host/realms/$realm",
    "auth_url": "https://$keycloak_host/realms/$realm/protocol/openid-connect/auth",
    "token_url": "https://$keycloak_host/realms/$realm/protocol/openid-connect/token",
    "userinfo_url": "https://$keycloak_host/realms/$realm/protocol/openid-connect/userinfo",
    "jwks_url": "https://$keycloak_host/realms/$realm/protocol/openid-connect/certs"
  },
  "clients": {
    "traefik": {
      "client_id": "traefik",
      "client_secret": "$traefik_client_secret",
      "redirect_uris": ["https://traefik.$keycloak_host/auth/callback"]
    },
    "portainer": {
      "client_id": "portainer", 
      "client_secret": "$portainer_client_secret",
      "redirect_uris": ["https://portainer.$keycloak_host/oauth/callback"]
    },
    "powerdns-admin": {
      "client_id": "powerdns-admin",
      "client_secret": "$pdns_admin_client_secret", 
      "redirect_uris": ["https://dns-admin.$keycloak_host/oidc/callback"]
    }
  }
}
EOF

  chmod 600 "$config_file"
  log "Authentication configuration saved to: $config_file"
}

main() {
  require_root
  
  echo "==========================="
  echo "Keycloak Configuration Setup"
  echo "==========================="
  echo
  
  # Check if Keycloak is running
  if ! docker service ls | grep -q "infrastructure_keycloak"; then
    err "Keycloak service not found. Please run the infrastructure setup first."
    exit 1
  fi
  
  echo "=== Keycloak Configuration ==="
  KEYCLOAK_HOST=$(prompt_default "Keycloak domain" "auth.example.com")
  KEYCLOAK_URL="https://$KEYCLOAK_HOST"
  
  echo "=== Admin User Configuration ==="
  ADMIN_EMAIL=$(prompt_default "Admin email address" "admin@$KEYCLOAK_HOST")
  ADMIN_PASSWORD=$(prompt_password "Admin password")
  ADMIN_FIRST_NAME=$(prompt_default "First name" "Admin")
  ADMIN_LAST_NAME=$(prompt_default "Last name" "User")
  
  echo "=== Realm Configuration ==="
  REALM_NAME=$(prompt_default "Realm name" "infrastructure")
  
  echo "=== Service Domains ==="
  TRAEFIK_HOST=$(prompt_default "Traefik domain" "traefik.${KEYCLOAK_HOST#auth.}")
  PORTAINER_HOST=$(prompt_default "Portainer domain" "portainer.${KEYCLOAK_HOST#auth.}")
  PDNS_ADMIN_HOST=$(prompt_default "PowerDNS Admin domain" "dns-admin.${KEYCLOAK_HOST#auth.}")
  
  # Wait for Keycloak to be ready
  wait_for_keycloak "$KEYCLOAK_URL" || exit 1
  
  # Get admin token (using bootstrap admin)
  log "Getting admin authentication token..."
  ADMIN_TOKEN=$(get_admin_token "$KEYCLOAK_URL" "admin" "$(cat /mnt/hosting/infrastructure/docker-compose.yml | grep KC_BOOTSTRAP_ADMIN_PASSWORD | cut -d: -f2 | tr -d ' ')" 2>/dev/null || {
    warn "Bootstrap admin login failed, trying with provided credentials..."
    get_admin_token "$KEYCLOAK_URL" "$ADMIN_EMAIL" "$ADMIN_PASSWORD"
  })
  
  if [[ -z "$ADMIN_TOKEN" ]]; then
    err "Failed to authenticate with Keycloak"
    exit 1
  fi
  
  # Create realm
  create_realm "$KEYCLOAK_URL" "$ADMIN_TOKEN" "$REALM_NAME"
  
  # Create admin user in new realm
  create_user "$KEYCLOAK_URL" "$ADMIN_TOKEN" "$REALM_NAME" "$ADMIN_EMAIL" "$ADMIN_PASSWORD" "$ADMIN_FIRST_NAME" "$ADMIN_LAST_NAME"
  
  # Create OIDC clients
  create_client "$KEYCLOAK_URL" "$ADMIN_TOKEN" "$REALM_NAME" "traefik" "Traefik Dashboard" "[\"https://$TRAEFIK_HOST/auth/callback\"]" "https://$TRAEFIK_HOST"
  
  create_client "$KEYCLOAK_URL" "$ADMIN_TOKEN" "$REALM_NAME" "portainer" "Portainer" "[\"https://$PORTAINER_HOST/oauth/callback\"]" "https://$PORTAINER_HOST"
  
  create_client "$KEYCLOAK_URL" "$ADMIN_TOKEN" "$REALM_NAME" "powerdns-admin" "PowerDNS Admin" "[\"https://$PDNS_ADMIN_HOST/oidc/callback\"]" "https://$PDNS_ADMIN_HOST"
  
  # Get client secrets
  log "Retrieving client secrets..."
  TRAEFIK_SECRET=$(get_client_secret "$KEYCLOAK_URL" "$ADMIN_TOKEN" "$REALM_NAME" "traefik")
  PORTAINER_SECRET=$(get_client_secret "$KEYCLOAK_URL" "$ADMIN_TOKEN" "$REALM_NAME" "portainer")
  PDNS_ADMIN_SECRET=$(get_client_secret "$KEYCLOAK_URL" "$ADMIN_TOKEN" "$REALM_NAME" "powerdns-admin")
  
  # Generate configuration files
  generate_auth_config "$KEYCLOAK_HOST" "$REALM_NAME" "$TRAEFIK_SECRET" "$PORTAINER_SECRET" "$PDNS_ADMIN_SECRET"
  
  # Update docker-compose with auth info
  update_docker_compose_for_auth "$KEYCLOAK_HOST" "$REALM_NAME" "$TRAEFIK_SECRET" "$PORTAINER_SECRET" "$PDNS_ADMIN_SECRET"
  
  echo
  log "Keycloak configuration completed successfully!"
  echo
  log "Configuration Summary:"
  log "- Keycloak URL: $KEYCLOAK_URL"
  log "- Realm: $REALM_NAME"  
  log "- Admin User: $ADMIN_EMAIL"
  log "- OIDC Clients: traefik, portainer, powerdns-admin"
  echo
  log "Configuration files:"
  log "- Auth config: /mnt/hosting/infrastructure/keycloak-auth-config.json"
  log "- Docker compose backup: /mnt/hosting/infrastructure/docker-compose.yml.backup.*"
  echo
  warn "Next steps:"
  warn "1. Configure each service to use OIDC authentication"
  warn "2. Update service-specific configuration files"
  warn "3. Restart services to apply authentication settings"
  warn "4. Test authentication flows for each service"
  echo
  log "Access Keycloak admin console at: $KEYCLOAK_URL/admin"
  log "Login with: $ADMIN_EMAIL / [provided password]"
}

main "$@"

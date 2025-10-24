# Host-Swarm Infrastructure Installer - Examples and Documentation

## Overview

The Host-Swarm Infrastructure Installer is a modular system for deploying and managing Docker Swarm infrastructure with:
- **Traefik** - Reverse proxy with automatic SSL
- **Portainer** - Docker management UI (optional)
- **Server Manager** - Centralized server management (optional)
- **Keycloak** - Identity provider for authentication (optional)

## Installation Process

The installer is broken into 6 modules that execute sequentially:

### Module 01: Docker Validation and Installation
- **Purpose**: Ensure Docker is installed and running
- **What it does**:
  - Checks if Docker is already installed
  - If not, installs Docker Engine, Docker Compose, and required tools
  - Enables and starts Docker service
- **Variables**: None (automatic)

### Module 02: Docker Swarm Setup
- **Purpose**: Initialize or join a Docker Swarm cluster
- **What it does**:
  - Checks if swarm is already active
  - Offers choice to:
    1. **Initiate new swarm** (makes this node the manager)
    2. **Connect to existing swarm** (makes this node a worker)
- **Variables**:
  - **For new swarm**: Advertise IP address (auto-detected)
  - **For joining**: Join token and manager IP address

### Module 03: Traefik Setup
- **Purpose**: Deploy Traefik reverse proxy with Cloudflare DNS challenge
- **What it does**:
  - Creates directory structure: `/mnt/hosting/infrastructure/traefik/`
  - Creates `traefik-net` overlay network
  - Deploys Traefik with automatic HTTPS via Let's Encrypt
  - Configures Cloudflare DNS challenge for wildcard certificates
- **Variables Required**:
  - `ACME_EMAIL` - Email for Let's Encrypt notifications
  - `TRAEFIK_DOMAIN` - Domain for Traefik dashboard (e.g., `traefik.example.com`)
  - `CF_API_EMAIL` - Cloudflare account email
  - `CF_DNS_API_TOKEN` - Cloudflare API token with DNS edit permissions
  - `TRAEFIK_USER` - Dashboard username (default: `admin`)
  - `TRAEFIK_PASSWORD` - Dashboard password
- **Created Files**:
  - `/mnt/hosting/infrastructure/traefik/.env`
  - `/mnt/hosting/infrastructure/traefik/docker-compose.yml`
  - `/mnt/hosting/infrastructure/traefik/letsencrypt/acme.json`

**Example Cloudflare API Token Setup**:
1. Go to Cloudflare Dashboard → My Profile → API Tokens
2. Create Token → Edit zone DNS template
3. Zone Resources: Include → Specific zone → your-domain.com
4. Copy the token for use in installation

### Module 04: Portainer Setup (Optional)
- **Purpose**: Deploy Portainer for web-based Docker management
- **What it does**:
  - Asks if you want to install Portainer
  - If yes, asks for exposure type:
    1. **Public** - Accessible via domain through Traefik (HTTPS)
    2. **Local** - Accessible via port 9000 directly
  - Creates directory structure: `/mnt/hosting/infrastructure/portainer/`
  - Deploys Portainer with agent in swarm mode
- **Variables Required**:
  - If **Public**: `PORTAINER_DOMAIN` (e.g., `portainer.example.com`)
  - If **Local**: No domain needed (exposes port 9000)
- **Created Files**:
  - `/mnt/hosting/infrastructure/portainer/docker-compose.yml`

### Module 05: Server Manager Setup (Optional)
- **Purpose**: Deploy or connect to centralized server management system
- **What it does**:
  - Asks if you want to install Server Manager
  - If yes, offers two modes:
    1. **Create new** - Deploy Server Manager on this server (becomes central manager)
    2. **Connect to existing** - Register this server with an existing manager
  - Generates SSH key pair for secure communication
  - Creates directory structure: `/mnt/hosting/infrastructure/server-manager/`
- **Variables Required**:
  
  **For Create Mode**:
  - `DOMAIN` - Domain for Server Manager (e.g., `manager.example.com`)
  - `ADMIN_EMAIL` - Admin email address
  - `ADMIN_PASSWORD` - Admin password
  - Auto-generated: `DB_PASSWORD`, SSH keys
  
  **For Connect Mode**:
  - `MANAGER_URL` - URL of existing Server Manager (e.g., `http://203.99.177.18:8080` or `https://manager.example.com`)
  - `CONNECTION_KEY` - Connection key from manager (64-character key)
- **Created Files**:
  - `/mnt/hosting/infrastructure/server-manager/.env` (create mode only)
  - `/mnt/hosting/infrastructure/server-manager/docker-compose.yml` (create mode only)
  - `/root/.ssh/server_manager_key` - SSH key pair
  - `/root/.ssh/authorized_keys` - Updated with manager's public key (connect mode)

**Connect Mode Process**:
1. Server generates SSH key
2. Validates connection key with manager via POST to `/api/server/ssh-key`
3. Receives manager's public key in response
4. Adds manager's public key to authorized_keys
5. Sends this server's public key to manager via POST to `/api/server/register-key`
6. Manager can now SSH into this server for management

### Module 06: Identity Provider Setup (Optional)
- **Purpose**: Deploy Keycloak for authentication and SSO
- **What it does**:
  - Only runs if Server Manager was installed
  - Asks if you want to install Keycloak
  - Deploys Keycloak with PostgreSQL database
  - Configures Keycloak for use with Server Manager
  - Creates directory structure: `/mnt/hosting/infrastructure/identity-provider/`
- **Variables Required**:
  - `KEYCLOAK_DOMAIN` - Domain for Keycloak (e.g., `auth.example.com`)
  - `KEYCLOAK_ADMIN` - Admin username (default: `admin`)
  - `KEYCLOAK_ADMIN_PASSWORD` - Admin password
  - Auto-generated: `KEYCLOAK_DB_PASSWORD`
- **Created Files**:
  - `/mnt/hosting/infrastructure/identity-provider/.env`
  - `/mnt/hosting/infrastructure/identity-provider/docker-compose.yml`

## Progress Tracking

The installer maintains a progress file at `/mnt/hosting/infrastructure/.install_progress.json`:

```json
{
  "started_at": "2025-10-23T10:30:00Z",
  "completed": false,
  "modules": {
    "01-docker": {
      "status": "completed",
      "timestamp": "2025-10-23T10:31:00Z"
    },
    "02-swarm": {
      "status": "in-progress",
      "timestamp": "2025-10-23T10:32:00Z"
    }
  },
  "portainer_installed": true,
  "server_manager_installed": true,
  "server_manager_mode": "create",
  "identity_provider_installed": true
}
```

## Running the Installer

### Fresh Installation
```bash
sudo ./setup.sh
```

### Resume Installation
If installation was interrupted, simply run again:
```bash
sudo ./setup.sh
```
The installer will detect pending installation and offer to:
1. Continue from where it left off
2. Start fresh (reset progress)

### Redo Completed Installation
If installation is complete, the installer offers:
1. Redo specific module
2. Redo entire installation
3. Exit

## Directory Structure

After installation, your infrastructure will be organized as:

```
/mnt/hosting/infrastructure/
├── .install_progress.json          # Installation progress tracker
├── traefik/
│   ├── .env                        # Traefik configuration
│   ├── docker-compose.yml          # Traefik stack definition
│   ├── letsencrypt/
│   │   └── acme.json              # SSL certificates storage
│   ├── dynamic/                    # Dynamic configuration
│   └── logs/                       # Access logs
├── portainer/
│   ├── docker-compose.yml          # Portainer stack definition
│   └── data/                       # Portainer data
├── server-manager/
│   ├── .env                        # Server Manager configuration
│   ├── docker-compose.yml          # Server Manager stack definition
│   ├── app/                        # Application data
│   └── mysql/                      # MySQL database
└── identity-provider/
    ├── .env                        # Keycloak configuration
    ├── docker-compose.yml          # Keycloak stack definition
    ├── data/                       # Keycloak data
    └── postgres/                   # PostgreSQL database
```

## Example Workflows

### Workflow 1: Simple Web Hosting Server
```
1. Module 01: Install Docker ✓
2. Module 02: Initialize new swarm ✓
3. Module 03: Setup Traefik with Cloudflare ✓
4. Module 04: Install Portainer (public) ✓
5. Module 05: Skip Server Manager
6. Module 06: Skip (requires Server Manager)
```

**Required Information**:
- Cloudflare API token
- Domains: `traefik.example.com`, `portainer.example.com`
- Email for Let's Encrypt
- Passwords for Traefik and Portainer

### Workflow 2: Central Management Server
```
1. Module 01: Install Docker ✓
2. Module 02: Initialize new swarm ✓
3. Module 03: Setup Traefik ✓
4. Module 04: Install Portainer (public) ✓
5. Module 05: Create Server Manager ✓
6. Module 06: Install Identity Provider ✓
```

**Required Information**:
- All domains: `traefik`, `portainer`, `manager`, `auth`
- Cloudflare API token
- Admin credentials for all services

### Workflow 3: Managed Server (Worker)
```
1. Module 01: Install Docker ✓
2. Module 02: Join existing swarm ✓
3. Module 03: Skip (only on manager)
4. Module 04: Skip (only on manager)
5. Module 05: Connect to existing Server Manager ✓
6. Module 06: Skip (only on manager)
```

**Required Information**:
- Swarm join token and manager IP
- Server Manager URL and connection key

## Accessing Services

After installation, services are accessible at:

- **Traefik Dashboard**: `https://traefik.example.com`
- **Portainer**: 
  - Public: `https://portainer.example.com`
  - Local: `http://<server-ip>:9000`
- **Server Manager**: `https://manager.example.com`
- **Keycloak**: `https://auth.example.com`

## Managing Stacks

Each service is deployed as a Docker stack:

```bash
# List all stacks
docker stack ls

# View services in a stack
docker stack services traefik
docker stack services portainer
docker stack services server-manager
docker stack services keycloak

# View logs
docker service logs traefik_traefik -f
docker service logs portainer_portainer -f

# Remove a stack
docker stack rm portainer

# Redeploy a stack
cd /mnt/hosting/infrastructure/traefik
docker stack deploy -c docker-compose.yml traefik
```

## Troubleshooting

### Check Installation Progress
```bash
cat /mnt/hosting/infrastructure/.install_progress.json | jq
```

### Reset Installation
```bash
sudo rm /mnt/hosting/infrastructure/.install_progress.json
sudo ./setup.sh
```

### Check Service Status
```bash
docker service ls
docker service ps <service-name>
docker service logs <service-name>
```

### Verify Networks
```bash
docker network ls | grep traefik
```

### Test Traefik
```bash
curl -k https://traefik.example.com
```

## Security Notes

1. **Environment Files**: All `.env` files are created with `600` permissions (owner read/write only)
2. **SSH Keys**: Generated with Ed25519 algorithm, stored in `/root/.ssh/`
3. **SSL Certificates**: Managed by Let's Encrypt via Cloudflare DNS challenge
4. **Passwords**: Database passwords are auto-generated with 32-byte random strings
5. **Firewall**: Ensure ports 80, 443, 2377 (swarm), and optionally 9000 (Portainer) are open

## Requirements

- **OS**: Debian/Ubuntu (other distros require manual Docker installation)
- **Root Access**: Required (use `sudo`)
- **Internet**: For downloading Docker and images
- **Cloudflare Account**: For DNS challenge and SSL certificates
- **Domains**: Pre-configured DNS records pointing to your server

## Support

For issues or questions:
1. Check service logs: `docker service logs <service-name>`
2. Verify installation progress: `cat .install_progress.json`
3. Review module scripts in `modules/` directory
4. Re-run specific module if needed

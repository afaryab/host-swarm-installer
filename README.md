# Host-Swarm Infrastructure Installer# Host-Swarm Infrastructure Installer# Host-Swarm Infrastructure Installer



A modular, automated installer for setting up complete Docker Swarm infrastructure with Traefik reverse proxy, Portainer management UI, Server Manager for multi-server orchestration, and Keycloak identity provider.



## OverviewA modular, automated installer for setting up complete Docker Swarm infrastructure with:A modular installation system for deploying Docker Swarm infrastructure with Traefik, Portainer, Keycloak, and Server Manager.



This installer provides a structured approach to deploying containerized infrastructure on Docker Swarm with automatic SSL certificates, centralized management, and optional components based on your needs.- **Docker Engine** - Container runtime



**Core Components:**- **Docker Swarm** - Container orchestration## Features

- Docker Engine - Container runtime

- Docker Swarm - Container orchestration- **Traefik** - Reverse proxy with automatic SSL via Let's Encrypt

- Traefik - Reverse proxy with automatic SSL via Let's Encrypt

- Portainer - Web-based Docker management (optional)- **Portainer** - Web-based Docker management UI (optional)- ✅ **Modular Installation**: Each component is installed separately via independent scripts

- Server Manager - Centralized multi-server management (optional)

- Keycloak - Identity provider and SSO (optional)- **Server Manager** - Centralized multi-server management (optional)- 📊 **Progress Tracking**: Installation progress is saved and can be resumed if interrupted



## Key Features- **Keycloak** - Identity provider and SSO (optional)- 🔄 **Resume Capability**: Continue from where you left off if installation fails



- **Modular Design** - 6 independent modules that execute sequentially- 🎯 **Selective Reinstall**: Redo specific sections without reinstalling everything

- **Progress Tracking** - Resume installation from interruption point

- **Interactive Configuration** - Variables collected per module, not all at once## ✨ Key Features- 📝 **Just-in-Time Configuration**: Variables are collected only when needed for each module

- **Organized Structure** - Each service in dedicated directory with own docker-compose.yml

- **Automatic SSL** - Let's Encrypt certificates via Cloudflare DNS challenge- 🌐 **Remote Execution**: Modules can be executed via curl from GitHub or locally

- **Multi-Server Support** - Create or join swarm clusters

- **SSH Key Management** - Automatic generation and exchange for server management- **🎯 Modular Design** - 6 independent modules that can be run separately

- **Flexible Reinstall** - Redo specific modules or entire installation

- **📊 Progress Tracking** - Resume installation from where you left off## Quick Start

## Prerequisites

- **🔄 Interactive** - Collects configuration per module, not all at once

- Ubuntu/Debian server (20.04 or later recommended)

- Root or sudo access- **🏗️ Organized Structure** - Each service in its own directory with docker-compose.yml### One-Line Installation

- Domain name with DNS managed by Cloudflare

- Cloudflare API token with DNS edit permissions- **🔒 Automatic SSL** - Let's Encrypt certificates via Cloudflare DNS challenge



## Installation- **🌐 Multi-Server** - Support for creating or joining swarm clusters```bash



### Quick Start- **🔑 SSH Key Management** - Automatic generation and exchange for server managementcurl -fsSL https://raw.githubusercontent.com/afaryab/host-swarm-installer/main/setup.sh | sudo bash



```bash- **↩️ Redo Capability** - Redo specific modules or entire installation```

# Clone the repository

git clone https://github.com/afaryab/host-swarm-installer.git

cd host-swarm-installer

## 📋 Prerequisites### Local Installation

# Make scripts executable

chmod +x setup.sh modules/*.sh



# Run the installer- Ubuntu/Debian server (20.04+ recommended)```bash

sudo ./setup.sh

```- Root or sudo accessgit clone https://github.com/afaryab/host-swarm-installer.git



### Installation Modules- Domain name with DNS managed by Cloudflarecd host-swarm-installer



The installer consists of 6 sequential modules:- Cloudflare API token with DNS edit permissionssudo bash setup.sh



**Module 01: Docker Validation and Installation**```

- Validates existing Docker installation

- Installs Docker Engine if not present## 🚀 Quick Start

- No user input required (automatic)

## Installation Modules

**Module 02: Docker Swarm Setup**

- Option 1: Initialize new swarm (manager node)```bash

- Option 2: Join existing swarm (worker node)

- Collects: Advertise IP (new) or join token + manager IP (existing)# Clone the repositoryThe installation is broken into the following modules:



**Module 03: Traefik Setup**git clone https://github.com/afaryab/host-swarm-installer.git

- Deploys Traefik reverse proxy

- Configures Cloudflare DNS challenge for SSLcd host-swarm-installer1. **Docker Engine** (`01-docker.sh`) - Installs Docker CE and required tools

- Collects: Email, domains, Cloudflare credentials, dashboard password

- Creates: `/mnt/hosting/infrastructure/traefik/`2. **Docker Swarm** (`02-swarm.sh`) - Initializes Docker Swarm mode



**Module 04: Portainer Setup (Optional)**# Make scripts executable3. **Directories & Networks** (`03-directories.sh`) - Creates directory structure and overlay networks

- User chooses whether to install

- If yes, choose deployment mode:chmod +x setup.sh modules/*.sh4. **Traefik & Portainer** (`04-traefik.sh`) - Deploys reverse proxy and container management

  - Public: Accessible via domain through Traefik (HTTPS)

  - Local: Accessible via port 90005. **Keycloak & Server Manager** (`05-keycloak.sh`) - Optional identity provider and management interface

- Creates: `/mnt/hosting/infrastructure/portainer/`

# Run the installer6. **Metrics Collection** (`06-metrics.sh`) - Sets up daily usage metrics collection

**Module 05: Server Manager (Optional)**

- User chooses whether to installsudo ./setup.sh

- Two operational modes:

  - **Create**: Deploy new Server Manager instance```## Progress Tracking

    - Collects: Domain, admin credentials

    - Generates: SSH keys, database passwords

  - **Connect**: Register with existing manager

    - Collects: Manager URL, connection key## 📦 Installation ModulesInstallation progress is stored in `/mnt/hosting/infrastructure/.install_progress.json`:

    - Exchanges: SSH public keys with manager

- Creates: `/mnt/hosting/infrastructure/server-manager/`



**Module 06: Identity Provider (Optional)**The installer is broken into 6 sequential modules:```json

- Conditional: Only runs if Server Manager installed

- User chooses whether to install Keycloak{

- Deploys Keycloak with PostgreSQL database

- Collects: Domain, admin credentials### 1️⃣ Module 01: Docker Validation and Installation  "started_at": "2025-10-23T10:30:00Z",

- Creates: `/mnt/hosting/infrastructure/identity-provider/`

- Validates Docker installation  "completed": false,

## Installation Behavior

- Installs Docker Engine if missing  "modules": {

### Fresh Installation

Run `sudo ./setup.sh` to execute all modules sequentially, collecting configuration for each module as it runs.- No configuration needed (automatic)    "01-docker": {



### Resume After Interruption      "status": "completed",

If installation is interrupted, run `sudo ./setup.sh` again. The installer will:

1. Detect pending installation### 2️⃣ Module 02: Docker Swarm Setup      "timestamp": "2025-10-23T10:31:00Z"

2. Show current progress

3. Offer options:- **Option 1**: Initialize new swarm (manager node)    },

   - Continue from where it left off

   - Start new installation (reset progress)- **Option 2**: Join existing swarm (worker node)    "02-swarm": {

   - Exit

- Collects: Advertise IP (new) or join token + manager IP (existing)      "status": "in-progress",

### Redo Completed Installation

If installation is already complete, run `sudo ./setup.sh` again. The installer will offer:      "timestamp": "2025-10-23T10:32:00Z"

1. Redo specific module (select from list)

2. Redo entire installation### 3️⃣ Module 03: Traefik Setup    }

3. Exit

- Deploys Traefik reverse proxy  }

## Directory Structure

- Configures Cloudflare DNS challenge for SSL}

After installation, infrastructure is organized as follows:

- Collects: Email, domains, Cloudflare credentials, dashboard password```

```

/mnt/hosting/infrastructure/- Creates: `/mnt/hosting/infrastructure/traefik/`

├── .install_progress.json          # Progress tracker

├── traefik/## Usage Scenarios

│   ├── .env

│   ├── docker-compose.yml### 4️⃣ Module 04: Portainer Setup (Optional)

│   ├── letsencrypt/acme.json

│   └── dynamic/- Asks: Install Portainer? (yes/no)### Fresh Installation

├── portainer/

│   ├── docker-compose.yml- If yes, asks: Public (with domain) or Local (port 9000)?

│   └── data/

├── server-manager/- Creates: `/mnt/hosting/infrastructure/portainer/`Simply run the script and it will guide you through all modules:

│   ├── .env

│   ├── docker-compose.yml

│   ├── app/

│   └── mysql/### 5️⃣ Module 05: Server Manager (Optional)```bash

└── identity-provider/

    ├── .env- Asks: Install Server Manager? (yes/no)sudo bash setup.sh

    ├── docker-compose.yml

    ├── data/- **Option 1**: Create new (central management server)```

    └── postgres/

```  - Collects: Domain, admin credentials



Each service maintains:  - Generates: SSH keys, database passwords### Resume Interrupted Installation

- Dedicated directory

- Environment file (.env)- **Option 2**: Connect to existing (managed server)

- Docker Compose file

- Data directories  - Collects: Manager URL, One-Time Token (OTT)If the installation is interrupted, run the script again:



## Service Access  - Exchanges: SSH public keys with manager



After successful installation, services are accessible at configured domains:- Creates: `/mnt/hosting/infrastructure/server-manager/````bash



| Service | Access Method |sudo bash setup.sh

|---------|---------------|

| Traefik Dashboard | https://traefik.example.com |### 6️⃣ Module 06: Identity Provider (Optional)```

| Portainer (Public) | https://portainer.example.com |

| Portainer (Local) | http://server-ip:9000 |- Only runs if Server Manager was installed

| Server Manager | https://manager.example.com |

| Keycloak | https://auth.example.com |- Asks: Install Keycloak? (yes/no)You'll be prompted with:



## Cloudflare API Token Setup- Deploys Keycloak with PostgreSQL- **Continue**: Resume from the last incomplete module



To create a Cloudflare API token for DNS challenge:- Collects: Domain, admin credentials- **Start Fresh**: Clear progress and restart



1. Log into Cloudflare Dashboard (https://dash.cloudflare.com)- Creates: `/mnt/hosting/infrastructure/identity-provider/`- **Exit**: Cancel

2. Navigate to My Profile → API Tokens

3. Click Create Token

4. Use Edit zone DNS template

5. Set Zone Resources: Include → Specific zone → your-domain.com## 🔄 Installation Behavior### Redo Completed Installation

6. Continue to summary → Create Token

7. Copy token for use during installation



## Example Deployment Scenarios### Fresh InstallationIf installation is already complete, you can:



### Scenario 1: Simple Web Hosting Server```bash

1. Install Docker

2. Initialize new swarmsudo ./setup.sh1. **Redo Specific Sections**: Select individual modules to reinstall

3. Setup Traefik

4. Install Portainer (public)```2. **Redo Everything**: Complete reinstallation (with option to keep or clear data)

5. Skip Server Manager

6. Skip Identity ProviderRuns all modules in sequence, collecting configuration per module.



Required: Cloudflare API token, domains for Traefik and Portainer, email for Let's Encrypt```bash



### Scenario 2: Central Management Server### Resume Installationsudo bash setup.sh

1. Install Docker

2. Initialize new swarmIf interrupted, run again:

3. Setup Traefik

4. Install Portainer```bash# Example output:

5. Create Server Manager

6. Install Identity Providersudo ./setup.sh# Installation is already complete. What would you like to do?



Required: Cloudflare API token, all service domains, admin credentials```#   1) Redo specific section(s)



### Scenario 3: Managed Worker NodeOffers to:#   2) Redo entire installation

1. Install Docker

2. Join existing swarm1. **Continue** from where it left off#   3) Exit

3. Skip Traefik (manager only)

4. Skip Portainer (manager only)2. **Start new** (reset progress)```

5. Connect to existing Server Manager

6. Skip Identity Provider (manager only)3. **Exit**



Required: Swarm join token, manager IP, Server Manager URL and connection key### Example: Redo Only Traefik Configuration



## Managing Services### Redo Installation



### Stack OperationsIf already complete, run again:```bash



```bash```bashsudo bash setup.sh

# List all stacks

docker stack lssudo ./setup.sh# Choose option 1



# List services in a stack```# Select "4" for Traefik & Portainer

docker stack services traefik

Offers to:# Confirm

# View service logs

docker service logs traefik_traefik -f1. **Redo specific module** (select from list)```

docker service logs portainer_portainer -f

2. **Redo entire installation**

# Check service status

docker service ps traefik_traefik3. **Exit**## Configuration Storage



# Redeploy a stack

cd /mnt/hosting/infrastructure/traefik

docker stack deploy -c docker-compose.yml traefik## 📂 Directory StructureModule configurations are stored in `/mnt/hosting/infrastructure/.install_config.json` for reuse across modules:



# Remove a stack

docker stack rm portainer

`````````json



### Service Updates/mnt/hosting/infrastructure/{



```bash├── .install_progress.json          # Progress tracker  "PRIMARY_DOMAIN": "example.com",

# Update service image

docker service update --image newimage:tag service_name├── traefik/  "ACME_EMAIL": "admin@example.com",



# Scale a service│   ├── .env  "TRAEFIK_HOST": "traefik.example.com",

docker service scale service_name=3

│   ├── docker-compose.yml  "PORTAINER_HOST": "portainer.example.com",

# Force update (recreate containers)

docker service update --force service_name│   ├── letsencrypt/acme.json  "KEYCLOAK_HOST": "login.example.com",

```

│   └── dynamic/  "SERVER_MANAGER_DOMAIN": "manager.example.com"

## Troubleshooting

├── portainer/}

### Check Installation Progress

│   ├── docker-compose.yml```

```bash

cat /mnt/hosting/infrastructure/.install_progress.json | jq│   └── data/

```

├── server-manager/## Module Development

### Reset and Start Over

│   ├── .env

```bash

sudo rm /mnt/hosting/infrastructure/.install_progress.json│   ├── docker-compose.ymlEach module is a standalone bash script that:

sudo ./setup.sh

```│   ├── app/



### Verify Swarm Status│   └── mysql/1. Can be executed independently



```bash└── identity-provider/2. Collects its own configuration variables

docker info | grep Swarm

docker node ls    ├── .env3. Loads shared config from `.install_config.json`

```

    ├── docker-compose.yml4. Saves new config values for other modules

### View Service Logs

    ├── data/5. Exits with status 0 on success, non-zero on failure

```bash

docker service logs traefik_traefik --tail 100 -f    └── postgres/

```

```### Module Template

### Check Networks



```bash

docker network ls | grep traefikEach service has its own:```bash

```

- Dedicated directory#!/usr/bin/env bash

### Verify SSL Certificates

- Environment file (`.env`)set -euo pipefail

```bash

cat /mnt/hosting/infrastructure/traefik/letsencrypt/acme.json | jq- Docker Compose file

```

- Data directorieslog() { echo -e "\033[1;32m[+] $*\033[0m"; }

## Documentation

err() { echo -e "\033[1;31m[✗] $*\033[0m"; }

For detailed information, refer to:

- **DOCUMENTATION.md** - Comprehensive guide with module details, variables, and examples## 🌐 Accessing Services

- **CHANGES.md** - Summary of changes from previous versions

- **WORKFLOW.md** - Visual workflow diagrammain() {

- **SUMMARY.md** - Implementation summary

After installation:  if [[ "${EUID}" -ne 0 ]]; then

## Security Features

    err "Please run as root (sudo)."

- Auto-generated secure passwords (32-byte random strings)

- Environment files created with 600 permissions (owner read/write only)| Service | Access |    exit 1

- SSH keys use Ed25519 algorithm

- All HTTP traffic automatically redirected to HTTPS|---------|--------|  fi

- Let's Encrypt SSL certificates via DNS challenge

- Traefik dashboard protected with basic authentication| Traefik Dashboard | `https://traefik.example.com` |  

- Internal services communicate via isolated overlay networks

| Portainer (Public) | `https://portainer.example.com` |  # Your module logic here

## Architecture

| Portainer (Local) | `http://<server-ip>:9000` |  log "Module completed successfully."

```

                    Internet| Server Manager | `https://manager.example.com` |}

                        ↓

                [Traefik :80/:443]| Keycloak | `https://auth.example.com` |

                        ↓

            [traefik-net overlay network]main "$@"

                        ↓

    ┌──────────┬────────┴────────┬──────────┐## 🔐 Cloudflare API Token Setup```

    ↓          ↓                 ↓          ↓

[Portainer] [Server Mgr]    [Keycloak] [Your Apps]

    ↓          ↓                 ↓

[Agent]    [MySQL]         [PostgreSQL]1. Log into [Cloudflare Dashboard](https://dash.cloudflare.com)## Environment Variables

```

2. Go to **My Profile** → **API Tokens**

## Contributing

3. Click **Create Token**- `INSTALLER_BASE_URL`: Base URL for downloading modules (default: GitHub raw content)

Contributions are welcome. For major changes, please open an issue first to discuss proposed modifications.

4. Use **Edit zone DNS** template

## License

5. Zone Resources: Include → Specific zone → `your-domain.com````bash

MIT License

6. Continue to summary → Create Token# Use local modules

## Support

7. Copy token for installationsudo bash setup.sh

- **Issues**: Report bugs or request features via GitHub issues

- **Logs**: Check service logs using `docker service logs service_name`

- **Progress**: View current installation state in .install_progress.json

- **Documentation**: Refer to DOCUMENTATION.md for comprehensive details## 📖 Example Workflows# Use custom URL


INSTALLER_BASE_URL="https://example.com/modules" sudo bash setup.sh

### Simple Web Hosting```

1. ✓ Install Docker

2. ✓ Initialize new swarm## Directory Structure

3. ✓ Setup Traefik

4. ✓ Install Portainer (public)```

5. ✗ Skip Server Manager/mnt/hosting/infrastructure/

6. ✗ Skip Identity Provider├── .install_progress.json       # Installation progress

├── .install_config.json         # Configuration values

### Central Management Server├── docker-compose.yml           # Generated stack file

1. ✓ Install Docker├── traefik/

2. ✓ Initialize new swarm│   ├── letsencrypt/

3. ✓ Setup Traefik│   │   └── acme.json

4. ✓ Install Portainer│   └── dynamic/

5. ✓ Create Server Manager│       ├── tls.yml

6. ✓ Install Identity Provider│       └── certs/

├── portainer/data/

### Managed Worker Node├── keycloak/

1. ✓ Install Docker│   ├── data/

2. ✓ Join existing swarm│   └── postgres/

3. ✗ Skip (manager only)├── server-manager/

4. ✗ Skip (manager only)│   ├── app/

5. ✓ Connect to existing Server Manager│   └── mysql/

6. ✗ Skip (manager only)└── metrics/

    ├── collect_usage.sh

## 🛠️ Managing Services    └── YYYY-MM-DD.json

```

```bash

# List all stacks## Services Deployed

docker stack ls

After successful installation:

# List services

docker service ls- **Traefik**: Reverse proxy with automatic SSL via Let's Encrypt

- **Portainer**: Docker Swarm management UI

# View service logs- **Keycloak** (optional): Identity and access management

docker service logs traefik_traefik -f- **Server Manager** (optional): Custom management interface

docker service logs portainer_portainer -f- **Metrics**: Daily usage collection timer



# Check service details## Requirements

docker service ps traefik_traefik

- Ubuntu/Debian Linux

# Update a service- Root access

docker service update --image newimage:tag service_name- Internet connectivity

- DNS records pointing to your server

# Redeploy a stack

cd /mnt/hosting/infrastructure/traefik## Troubleshooting

docker stack deploy -c docker-compose.yml traefik

### Installation Failed

# Remove a stack

docker stack rm portainerCheck the progress file to see which module failed:

```

```bash

## 🔧 Troubleshootingcat /mnt/hosting/infrastructure/.install_progress.json

```

### Check Installation Progress

```bashRun the failed module manually:

cat /mnt/hosting/infrastructure/.install_progress.json | jq

``````bash

sudo bash ./modules/XX-modulename.sh

### Reset and Start Over```

```bash

sudo rm /mnt/hosting/infrastructure/.install_progress.json### Reset Everything

sudo ./setup.sh

``````bash

sudo rm -rf /mnt/hosting/infrastructure

### Check Swarm Statussudo docker stack rm infrastructure

```bashsudo docker system prune -af --volumes

docker info | grep Swarm```

docker node ls

```## License



### View Service LogsMIT License - See LICENSE file for details

```bash

docker service logs traefik_traefik --tail 100 -f# Documentation

```

## Installation

### Verify Networks

```bashTo install the Host Swarm environment, run the following command in your terminal:

docker network ls | grep traefik

``````curl

curl -O https://raw.githubusercontent.com/afaryab/host-swarm-installer/main/setup.sh

## 📚 Documentationchmod +x setup.sh

sudo ./setup.sh

For detailed information, see [DOCUMENTATION.md](DOCUMENTATION.md) which includes:```
- Detailed module descriptions
- Required variables for each module
- Directory structure details
- Troubleshooting guide
- Security notes
- Example configurations

## Security Features

- Auto-generated secure passwords (32-byte random)
- Environment files created with `600` permissions
- SSH keys use Ed25519 algorithm
- All HTTP traffic redirected to HTTPS
- Let's Encrypt SSL certificates
- Traefik dashboard protected with basic auth
- Internal services use overlay networks

## Architecture

```
                                Internet
                                   ↓
                            [Traefik :80/:443]
                                   ↓
                        [traefik-net overlay]
                                   ↓
        ┌──────────────┬────────────────┬──────────────────┐
        ↓              ↓                ↓                  ↓
   [Portainer]  [Server Manager]  [Keycloak]         [Your Apps]
        ↓              ↓                ↓
    [Agent]        [MySQL]         [PostgreSQL]
```

## Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.

## License

MIT

## Support

- **Issues**: Open a GitHub issue
- **Logs**: Check service logs with `docker service logs <service>`
- **Progress**: View `.install_progress.json` for current state
- **Docs**: See [DOCUMENTATION.md](DOCUMENTATION.md) for details

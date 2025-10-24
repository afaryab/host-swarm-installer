# Installation Script Changes - October 23, 2025

## Summary

The Host-Swarm Infrastructure Installer has been completely restructured into a modular, interactive system with the following major improvements:

## Major Changes

### 1. Modular Architecture
- **Before**: Single monolithic setup.sh with all configurations collected upfront
- **After**: 6 independent module scripts that collect variables just-in-time

### 2. Module Breakdown

#### Module 01: Docker Validation and Installation (`01-docker.sh`)
- Validates existing Docker installation
- Installs Docker if missing
- No user input required (automatic)

#### Module 02: Docker Swarm Setup (`02-swarm.sh`)
- Interactive choice: Initiate new swarm OR Join existing swarm
- **New swarm**: Collects advertise IP
- **Join swarm**: Collects join token and manager IP
- Replaces old automatic swarm initialization

#### Module 03: Traefik Setup (`03-traefik.sh`)
- Creates dedicated `/mnt/hosting/infrastructure/traefik/` directory
- Individual `docker-compose.yml` for Traefik stack
- Collects variables on-demand:
  - ACME email
  - Traefik domain
  - Cloudflare credentials
  - Dashboard credentials
- Deploys Traefik as separate stack

#### Module 04: Portainer Setup (`04-portainer.sh`)
- **NEW**: Optional installation (asks user)
- **NEW**: Deployment mode choice:
  - Public (via Traefik with domain)
  - Local (port 9000 exposure)
- Creates dedicated `/mnt/hosting/infrastructure/portainer/` directory
- Individual `docker-compose.yml` for Portainer stack
- Deploys as separate stack

#### Module 05: Server Manager Setup (`05-server-manager.sh`)
- **NEW**: Optional installation (asks user)
- **NEW**: Two modes:
  1. **Create Server** - Deploy new Server Manager
     - Collects domain, admin credentials
     - Generates SSH keys automatically
     - Creates MySQL database
  2. **Connect to existing** - Register this server with an existing manager
     - Collects manager URL and connection key
     - Generates local SSH key
     - Sends registration request with public key
     - Receives manager's public key
     - Adds to authorized_keys for SSH access
- Creates dedicated `/mnt/hosting/infrastructure/server-manager/` directory
- Individual `docker-compose.yml` (create mode only)
- Deployed as separate stack

#### Module 06: Identity Provider Setup (`06-identity-provider.sh`)
- **NEW**: Optional installation (asks user)
- **CONDITIONAL**: Only runs if Server Manager was installed
- Deploys Keycloak with PostgreSQL
- Collects domain and admin credentials
- Creates dedicated `/mnt/hosting/infrastructure/identity-provider/` directory
- Individual `docker-compose.yml` for Keycloak stack
- Deployed as separate stack

### 3. Progress Tracking System

#### Enhanced Progress File (`/mnt/hosting/infrastructure/.install_progress.json`)
```json
{
  "started_at": "2025-10-23T10:30:00Z",
  "completed": false,
  "modules": {
    "01-docker": {"status": "completed", "timestamp": "..."},
    "02-swarm": {"status": "completed", "timestamp": "..."},
    ...
  },
  "portainer_installed": true,
  "server_manager_installed": true,
  "server_manager_mode": "create",
  "identity_provider_installed": true
}
```

#### Status Values
- `not-started` - Module hasn't been executed
- `in-progress` - Module is currently running
- `completed` - Module finished successfully
- `failed` - Module encountered an error

### 4. Interactive Resume Capability

#### Previous Installation Pending
When re-running with incomplete installation:
1. Shows progress summary
2. Offers choices:
   - Continue from where left off
   - Start new installation (reset progress)
   - Exit

#### Installation Already Complete
When re-running after successful installation:
1. Shows completion status
2. Offers choices:
   - Redo specific module (select from list)
   - Redo entire installation
   - Exit

### 5. Directory Structure Changes

#### Before
```
/mnt/hosting/infrastructure/
├── docker-compose.yml           # Single monolithic file
├── traefik/
├── portainer/
├── keycloak/
└── server-manager/
```

#### After
```
/mnt/hosting/infrastructure/
├── .install_progress.json       # Progress tracker
├── traefik/
│   ├── .env                     # Environment variables
│   ├── docker-compose.yml       # Traefik stack only
│   └── letsencrypt/acme.json
├── portainer/
│   └── docker-compose.yml       # Portainer stack only
├── server-manager/
│   ├── .env
│   └── docker-compose.yml       # Server Manager stack only
└── identity-provider/
    ├── .env
    └── docker-compose.yml       # Keycloak stack only
```

**Key Change**: Each service now has its own `docker-compose.yml` and is deployed as an independent Docker stack.

### 6. Stack Deployment

#### Before
```bash
docker stack deploy -c docker-compose.yml infrastructure
```
Single stack for all services.

#### After
```bash
docker stack deploy -c docker-compose.yml traefik
docker stack deploy -c docker-compose.yml portainer
docker stack deploy -c docker-compose.yml server-manager
docker stack deploy -c docker-compose.yml keycloak
```
Each service is an independent stack, can be managed separately.

### 7. Variable Collection

#### Before
- All variables collected at the start
- User had to know all values upfront
- Long initial configuration session

#### After
- Variables collected per module when needed
- Module 03 asks for Traefik config when it runs
- Module 04 asks for Portainer config when it runs
- Much better user experience

### 8. SSH Key Management (New Feature)

#### Server Manager Create Mode
- Generates SSH key pair: `/root/.ssh/server_manager_key`
- Public key included in Server Manager deployment
- Used for server-to-server communication

#### Server Manager Connect Mode
1. Generates local SSH key
2. Sends public key to manager via API
3. Receives manager's public key in response
4. Adds manager's key to `/root/.ssh/authorized_keys`
5. Manager can now SSH into this server

### 9. Optional Components

Services that are now optional with user prompts:
- ✓ **Portainer** - Can skip if not needed
- ✓ **Server Manager** - Can skip if not needed
- ✓ **Identity Provider** - Can skip if Server Manager not installed

Core services (always installed):
- ✓ **Docker** - Required
- ✓ **Swarm** - Required
- ✓ **Traefik** - Required

## Benefits of New Structure

1. **Modularity** - Each module is independent and reusable
2. **Flexibility** - User can skip optional components
3. **Resilience** - Failed module can be rerun without affecting others
4. **Maintainability** - Each service has its own configuration
5. **Clarity** - Clear separation of concerns
6. **Scalability** - Easy to add new modules
7. **User Experience** - Progressive disclosure of configuration
8. **Debugging** - Easier to identify and fix issues per module

## Migration Notes

### If You Have Existing Installation

The new structure is **not backward compatible** with the old monolithic approach. To migrate:

1. Back up existing data directories
2. Note your current configuration
3. Remove old infrastructure stack:
   ```bash
   docker stack rm infrastructure
   ```
4. Run new installer:
   ```bash
   sudo ./setup.sh
   ```
5. Restore data if needed

### If Starting Fresh

Simply run the new installer - it will guide you through each step interactively.

## File Changes

### New Files
- `modules/01-docker.sh` - Updated with validation
- `modules/02-swarm.sh` - Updated with join capability
- `modules/03-traefik.sh` - New modular version
- `modules/04-portainer.sh` - New with optional + mode selection
- `modules/05-server-manager.sh` - New with create/connect modes
- `modules/06-identity-provider.sh` - New with conditional installation
- `setup.sh` - Complete rewrite as orchestrator
- `DOCUMENTATION.md` - Comprehensive guide
- `README.md` - Updated with new workflow
- `CHANGES.md` - This file

### Backed Up Files
- `setup.sh.old` - Original setup script
- `README.md.old` - Original README
- `setup.sh.backup` - Previous backup

### Removed Files
- Old module files that were part of previous structure

## Testing Recommendations

Before deploying to production:

1. Test fresh installation on clean server
2. Test resume capability (interrupt and continue)
3. Test redo specific module
4. Test all optional component combinations
5. Test swarm join functionality
6. Test Server Manager connect mode
7. Verify all stacks deploy correctly
8. Check inter-service communication

## Future Enhancements

Potential improvements for future versions:

1. Add rollback capability per module
2. Support for non-Cloudflare DNS providers
3. Automated backup before redo operations
4. Health checks and validation after each module
5. Support for custom module paths
6. Configuration file support (YAML/JSON)
7. Non-interactive mode with env vars
8. Module dependency validation

## Questions or Issues?

- Check DOCUMENTATION.md for detailed information
- Review module scripts in `modules/` directory
- Check `.install_progress.json` for current state
- Open GitHub issue for bugs or feature requests

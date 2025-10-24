# Host-Swarm Installer - Workflow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│                  HOST-SWARM INSTALLER WORKFLOW                      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

                            ┌──────────────┐
                            │  setup.sh    │
                            │  (Main)      │
                            └──────┬───────┘
                                   │
                         ┌─────────▼──────────┐
                         │  Check Progress    │
                         │  .install_progress │
                         └─────────┬──────────┘
                                   │
                    ┌──────────────┼──────────────┐
                    │              │              │
            ┌───────▼────────┐ ┌──▼──────┐ ┌────▼────────┐
            │  No Progress   │ │ Pending │ │  Completed  │
            │  (Fresh)       │ │         │ │             │
            └───────┬────────┘ └──┬──────┘ └────┬────────┘
                    │              │              │
                    │        ┌─────▼─────┐   ┌───▼─────────┐
                    │        │ Continue? │   │ Redo Menu?  │
                    │        │ or Reset  │   │ - Specific  │
                    │        └─────┬─────┘   │ - All       │
                    │              │         │ - Exit      │
                    └──────────────┴─────────┴─────┬───────┘
                                                   │
                              ┌────────────────────▼────────────────────┐
                              │     Execute Modules in Sequence         │
                              └─────────────────────────────────────────┘

╔════════════════════════════════════════════════════════════════════╗
║                        MODULE 01: DOCKER                           ║
╠════════════════════════════════════════════════════════════════════╣
║  ┌────────────────────┐                                            ║
║  │ Check if Docker    │───NO──► Install Docker Engine              ║
║  │ is installed       │                                            ║
║  └──────┬─────────────┘                                            ║
║         │                                                           ║
║        YES                                                          ║
║         │                                                           ║
║  ┌──────▼─────────────┐                                            ║
║  │  Validate Version  │                                            ║
║  └────────────────────┘                                            ║
║                                                                     ║
║  📁 Creates: None (system-level install)                           ║
║  ⚙️  Variables: None (automatic)                                   ║
║  ✅ Status: completed                                              ║
╚════════════════════════════════════════════════════════════════════╝
                              │
╔═════════════════════════════▼══════════════════════════════════════╗
║                        MODULE 02: SWARM                            ║
╠════════════════════════════════════════════════════════════════════╣
║  ┌────────────────────┐                                            ║
║  │ Check Swarm Status │───ACTIVE──► Skip (already in swarm)        ║
║  └──────┬─────────────┘                                            ║
║         │                                                           ║
║      INACTIVE                                                       ║
║         │                                                           ║
║  ┌──────▼─────────────┐                                            ║
║  │ User Choice:       │                                            ║
║  │ 1) Init new swarm  │                                            ║
║  │ 2) Join existing   │                                            ║
║  └──────┬─────────────┘                                            ║
║         │                                                           ║
║    ┌────┴─────┐                                                    ║
║    │          │                                                     ║
║  ┌─▼──────┐ ┌▼────────┐                                           ║
║  │ Init   │ │ Join    │                                            ║
║  │ Swarm  │ │ Swarm   │                                            ║
║  └────────┘ └─────────┘                                            ║
║                                                                     ║
║  📁 Creates: None (swarm management)                               ║
║  ⚙️  Variables:                                                    ║
║     - Advertise IP (init mode)                                     ║
║     - Join token + Manager IP (join mode)                          ║
║  ✅ Status: completed                                              ║
╚════════════════════════════════════════════════════════════════════╝
                              │
╔═════════════════════════════▼══════════════════════════════════════╗
║                       MODULE 03: TRAEFIK                           ║
╠════════════════════════════════════════════════════════════════════╣
║  ┌──────────────────────────────────────────┐                     ║
║  │ Create Directories                       │                     ║
║  │ /mnt/hosting/infrastructure/traefik/     │                     ║
║  │   ├── letsencrypt/                       │                     ║
║  │   ├── dynamic/                           │                     ║
║  │   └── logs/                              │                     ║
║  └────────────┬─────────────────────────────┘                     ║
║               │                                                     ║
║  ┌────────────▼─────────────────────────────┐                     ║
║  │ Create traefik-net overlay network       │                     ║
║  └────────────┬─────────────────────────────┘                     ║
║               │                                                     ║
║  ┌────────────▼─────────────────────────────┐                     ║
║  │ Collect Variables:                       │                     ║
║  │  - ACME Email                            │                     ║
║  │  - Traefik Domain                        │                     ║
║  │  - Cloudflare API Email                  │                     ║
║  │  - Cloudflare DNS API Token              │                     ║
║  │  - Dashboard Username                    │                     ║
║  │  - Dashboard Password                    │                     ║
║  └────────────┬─────────────────────────────┘                     ║
║               │                                                     ║
║  ┌────────────▼─────────────────────────────┐                     ║
║  │ Generate .env file                       │                     ║
║  └────────────┬─────────────────────────────┘                     ║
║               │                                                     ║
║  ┌────────────▼─────────────────────────────┐                     ║
║  │ Generate docker-compose.yml              │                     ║
║  └────────────┬─────────────────────────────┘                     ║
║               │                                                     ║
║  ┌────────────▼─────────────────────────────┐                     ║
║  │ docker stack deploy -c ... traefik       │                     ║
║  └──────────────────────────────────────────┘                     ║
║                                                                     ║
║  📁 Creates: /mnt/hosting/infrastructure/traefik/                 ║
║  ⚙️  Variables: Email, domains, Cloudflare creds                  ║
║  ✅ Status: completed                                              ║
╚════════════════════════════════════════════════════════════════════╝
                              │
╔═════════════════════════════▼══════════════════════════════════════╗
║                      MODULE 04: PORTAINER                          ║
╠════════════════════════════════════════════════════════════════════╣
║  ┌────────────────────┐                                            ║
║  │ Install Portainer? │───NO──► Skip (save choice to progress)    ║
║  └──────┬─────────────┘                                            ║
║         │                                                           ║
║        YES                                                          ║
║         │                                                           ║
║  ┌──────▼─────────────────────────────────┐                       ║
║  │ Create Directories                     │                       ║
║  │ /mnt/hosting/infrastructure/portainer/ │                       ║
║  │   └── data/                            │                       ║
║  └──────┬─────────────────────────────────┘                       ║
║         │                                                           ║
║  ┌──────▼─────────────┐                                            ║
║  │ Deployment Mode:   │                                            ║
║  │ 1) Public (domain) │                                            ║
║  │ 2) Local (port)    │                                            ║
║  └──────┬─────────────┘                                            ║
║         │                                                           ║
║    ┌────┴─────┐                                                    ║
║    │          │                                                     ║
║  ┌─▼──────┐ ┌▼────────┐                                           ║
║  │ Public │ │ Local   │                                            ║
║  │ Setup  │ │ Setup   │                                            ║
║  └────┬───┘ └───┬─────┘                                            ║
║       │         │                                                   ║
║       │    ┌────▼─────────────────────────────┐                   ║
║       │    │ Generate docker-compose.yml      │                   ║
║       │    │ (with or without Traefik labels) │                   ║
║       │    └────┬─────────────────────────────┘                   ║
║       │         │                                                   ║
║       │    ┌────▼─────────────────────────────┐                   ║
║       │    │ docker stack deploy ... portainer│                   ║
║       │    └──────────────────────────────────┘                   ║
║       │                                                             ║
║  📁 Creates: /mnt/hosting/infrastructure/portainer/               ║
║  ⚙️  Variables: Domain (if public)                                ║
║  ✅ Status: completed (or skipped)                                ║
╚════════════════════════════════════════════════════════════════════╝
                              │
╔═════════════════════════════▼══════════════════════════════════════╗
║                    MODULE 05: SERVER MANAGER                       ║
╠════════════════════════════════════════════════════════════════════╣
║  ┌──────────────────────────┐                                      ║
║  │ Install Server Manager?  │───NO──► Skip (save choice)          ║
║  └──────┬───────────────────┘                                      ║
║         │                                                           ║
║        YES                                                          ║
║         │                                                           ║
║  ┌──────▼───────────────────────────────────┐                     ║
║  │ Create Directories                       │                     ║
║  │ /mnt/hosting/infrastructure/             │                     ║
║  │   server-manager/                        │                     ║
║  │     ├── app/                             │                     ║
║  │     └── mysql/                           │                     ║
║  └──────┬───────────────────────────────────┘                     ║
║         │                                                           ║
║  ┌──────▼─────────────┐                                            ║
║  │ Mode Choice:       │                                            ║
║  │ 1) Create new      │                                            ║
║  │ 2) Connect         │                                            ║
║  └──────┬─────────────┘                                            ║
║         │                                                           ║
║    ┌────┴─────┐                                                    ║
║    │          │                                                     ║
║  ┌─▼──────────────────────┐  ┌─▼─────────────────────┐           ║
║  │ CREATE MODE            │  │ CONNECT MODE           │           ║
║  │                        │  │                        │           ║
║  │ 1. Collect:            │  │ 1. Collect:            │           ║
║  │    - Domain            │  │    - Manager URL       │           ║
║  │    - Admin email       │  │    - OTT token         │           ║
║  │    - Admin password    │  │    - Server name       │           ║
║  │                        │  │                        │           ║
║  │ 2. Generate:           │  │ 2. Generate:           │           ║
║  │    - SSH keys          │  │    - SSH keys          │           ║
║  │    - DB password       │  │                        │           ║
║  │                        │  │ 3. API Call:           │           ║
║  │ 3. Create:             │  │    - POST registration │           ║
║  │    - .env file         │  │    - Send public key   │           ║
║  │    - docker-compose    │  │    - Receive mgr key   │           ║
║  │                        │  │                        │           ║
║  │ 4. Deploy:             │  │ 4. Add to:             │           ║
║  │    - Stack deploy      │  │    - authorized_keys   │           ║
║  └────────────────────────┘  └────────────────────────┘           ║
║                                                                     ║
║  📁 Creates: /mnt/hosting/infrastructure/server-manager/          ║
║              /root/.ssh/server_manager_key                        ║
║  ⚙️  Variables: Domain, creds (create) or URL, OTT (connect)     ║
║  ✅ Status: completed (or skipped)                                ║
╚════════════════════════════════════════════════════════════════════╝
                              │
╔═════════════════════════════▼══════════════════════════════════════╗
║                  MODULE 06: IDENTITY PROVIDER                      ║
╠════════════════════════════════════════════════════════════════════╣
║  ┌──────────────────────────────────────┐                         ║
║  │ Check if Server Manager installed    │───NO──► Skip            ║
║  └──────┬───────────────────────────────┘                         ║
║         │                                                           ║
║        YES                                                          ║
║         │                                                           ║
║  ┌──────▼────────────────────┐                                     ║
║  │ Install Keycloak?         │───NO──► Skip (save choice)         ║
║  └──────┬────────────────────┘                                     ║
║         │                                                           ║
║        YES                                                          ║
║         │                                                           ║
║  ┌──────▼───────────────────────────────┐                         ║
║  │ Create Directories                   │                         ║
║  │ /mnt/hosting/infrastructure/         │                         ║
║  │   identity-provider/                 │                         ║
║  │     ├── data/                        │                         ║
║  │     └── postgres/                    │                         ║
║  └──────┬───────────────────────────────┘                         ║
║         │                                                           ║
║  ┌──────▼───────────────────────────────┐                         ║
║  │ Collect Variables:                   │                         ║
║  │  - Keycloak Domain                   │                         ║
║  │  - Admin Username                    │                         ║
║  │  - Admin Password                    │                         ║
║  └──────┬───────────────────────────────┘                         ║
║         │                                                           ║
║  ┌──────▼───────────────────────────────┐                         ║
║  │ Generate DB password                 │                         ║
║  └──────┬───────────────────────────────┘                         ║
║         │                                                           ║
║  ┌──────▼───────────────────────────────┐                         ║
║  │ Generate .env file                   │                         ║
║  └──────┬───────────────────────────────┘                         ║
║         │                                                           ║
║  ┌──────▼───────────────────────────────┐                         ║
║  │ Generate docker-compose.yml          │                         ║
║  └──────┬───────────────────────────────┘                         ║
║         │                                                           ║
║  ┌──────▼───────────────────────────────┐                         ║
║  │ docker stack deploy -c ... keycloak  │                         ║
║  └──────────────────────────────────────┘                         ║
║                                                                     ║
║  📁 Creates: /mnt/hosting/infrastructure/identity-provider/       ║
║  ⚙️  Variables: Domain, admin credentials                         ║
║  ✅ Status: completed (or skipped)                                ║
╚════════════════════════════════════════════════════════════════════╝
                              │
                   ┌──────────▼──────────┐
                   │  Mark Installation  │
                   │  as Completed       │
                   └──────────┬──────────┘
                              │
                   ┌──────────▼──────────┐
                   │  Show Summary       │
                   │  & Access Info      │
                   └─────────────────────┘

═══════════════════════════════════════════════════════════════════

DEPLOYED DOCKER STACKS:

  ┌─────────────┐  ┌──────────────┐  ┌─────────────────┐  ┌──────────┐
  │  traefik    │  │  portainer   │  │ server-manager  │  │ keycloak │
  │             │  │              │  │                 │  │          │
  │ (required)  │  │  (optional)  │  │   (optional)    │  │(optional)│
  └─────────────┘  └──────────────┘  └─────────────────┘  └──────────┘
         │                 │                  │                  │
         └─────────────────┴──────────────────┴──────────────────┘
                                    │
                            [traefik-net]
                                    │
                              [Internet]

═══════════════════════════════════════════════════════════════════

DIRECTORY STRUCTURE AFTER INSTALLATION:

/mnt/hosting/infrastructure/
├── .install_progress.json
├── traefik/
│   ├── .env
│   ├── docker-compose.yml
│   ├── letsencrypt/acme.json
│   ├── dynamic/
│   └── logs/
├── portainer/
│   ├── docker-compose.yml
│   └── data/
├── server-manager/
│   ├── .env
│   ├── docker-compose.yml
│   ├── app/
│   └── mysql/
└── identity-provider/
    ├── .env
    ├── docker-compose.yml
    ├── data/
    └── postgres/

═══════════════════════════════════════════════════════════════════
```

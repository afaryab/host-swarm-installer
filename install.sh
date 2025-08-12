#!/bin/bash
set -e

SETUP_URL="https://raw.githubusercontent.com/afaryab/host-swarm-installer/main/setup.sh"

curl -fsSL "$SETUP_URL" | bash
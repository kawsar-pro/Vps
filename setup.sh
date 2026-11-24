
#!/usr/bin/env bash

# GitHub Ubuntu VPS Setup - No Tailscale

set -Eeuo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[SETUP]${NC} $*"
}

err() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

VPS_USER="${VPS_USER:-kawsar}"
VPS_PASSWORD="${VPS_PASSWORD:-kawsar}"
ENABLE_DOCKER="${ENABLE_DOCKER:-true}"

log "Updating package lists..."
sudo apt-get update -y

log "Installing packages..."

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    git curl wget unzip zip \
    ca-certificates gnupg \
    python3 python3-pip python3-venv \
    nodejs npm build-essential \
    vim nano htop net-tools dnsutils \
    openssh-server tmate

log "Creating VPS user..."

if ! id "$VPS_USER" >/dev/null 2>&1; then
    sudo useradd -m -s /bin/bash "$VPS_USER"
fi

echo "$VPS_USER:$VPS_PASSWORD" | sudo chpasswd

sudo usermod -aG sudo "$VPS_USER"

echo "$VPS_USER ALL=(ALL) NOPASSWD:ALL" | \
    sudo tee "/etc/sudoers.d/$VPS_USER" >/dev/null

sudo chmod 0440 "/etc/sudoers.d/$VPS_USER"
sudo visudo -cf "/etc/sudoers.d/$VPS_USER"

if [ "$ENABLE_DOCKER" = "true" ]; then
    log "Installing Docker..."

    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io

    sudo systemctl enable --now docker
    sudo usermod -aG docker "$VPS_USER"
fi

log "Configuring SSH..."

sudo mkdir -p /run/sshd

sudo tee /etc/ssh/sshd_config.d/99-vps.conf >/dev/null <<EOF
PasswordAuthentication yes
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
AllowUsers $VPS_USER
EOF

sudo sshd -t

sudo systemctl enable ssh
sudo systemctl restart ssh

if ! sudo systemctl is-active --quiet ssh; then
    err "SSH service failed."
    exit 1
fi

log "Checking tmate..."

if ! command -v tmate >/dev/null 2>&1; then
    err "Tmate installation failed."
    exit 1
fi

log "Cleaning package cache..."

sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

log "======================================"
log "VPS SETUP COMPLETED"
log "Username: $VPS_USER"
log "SSH Port: 22"
log "======================================"

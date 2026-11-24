#!/usr/bin/env bash
#
# setup.sh - Prepares a fresh Linux runner as a temporary VPS.
#
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[SETUP]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

VPS_USER="${VPS_USER:-vpsuser}"
VPS_PASSWORD="${VPS_PASSWORD:-changeme123}"
TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY:-}"
VPS_HOSTNAME="${VPS_HOSTNAME:-gh-vps}"
ENABLE_DOCKER="${ENABLE_DOCKER:-true}"

if [ -z "$VPS_PASSWORD" ]; then
  err "VPS_PASSWORD cannot be empty"
  exit 1
fi

log "Updating package lists..."
sudo apt-get update -y

log "Installing base tools..."
sudo apt-get install -y --no-install-recommends \
  git curl wget unzip zip ca-certificates gnupg lsb-release \
  python3 python3-pip python3-venv \
  nodejs npm \
  build-essential \
  vim nano htop \
  net-tools dnsutils \
  openssh-server \
  tmate

if [ "$ENABLE_DOCKER" = "true" ]; then
  log "Installing Docker..."
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  sudo systemctl enable docker
  sudo systemctl start docker
fi

log "Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

if [ -n "$TAILSCALE_AUTHKEY" ]; then
  log "Starting tailscaled..."
  sudo systemctl enable tailscaled
  sudo systemctl start tailscaled

  # Wait for tailscaled socket to be ready before calling tailscale up
  for i in $(seq 1 10); do
    if sudo tailscale status >/dev/null 2>&1; then
      break
    fi
    log "Waiting for tailscaled... ($i/10)"
    sleep 2
  done

  log "Running tailscale up..."
  sudo tailscale up \
    --authkey="$TAILSCALE_AUTHKEY" \
    --hostname="$VPS_HOSTNAME" \
    --accept-routes || warn "tailscale up returned non-zero"

  # Poll for IPv4 assignment — up to 30 seconds
  log "Waiting for Tailscale IP assignment..."
  TS_IP=""
  for i in $(seq 1 15); do
    TS_IP=$(tailscale ip -4 2>/dev/null || true)
    if [ -n "$TS_IP" ]; then
      log "Tailscale connected — IP: $TS_IP"
      break
    fi
    log "No IP yet, retrying... ($i/15)"
    sleep 2
  done

  if [ -z "$TS_IP" ]; then
    warn "Tailscale did not assign an IPv4 within 30 seconds — check your auth key and ACL policy"
  fi
else
  warn "TAILSCALE_AUTHKEY not set — Tailscale will not connect"
  warn "Add TAILSCALE_AUTHKEY to your repository secrets at:"
  warn "  Settings -> Secrets and variables -> Actions -> New repository secret"
  warn "Get a reusable auth key from: https://login.tailscale.com/admin/settings/keys"
fi

log "Creating user '$VPS_USER'..."
if ! id -u "$VPS_USER" >/dev/null 2>&1; then
  sudo useradd -m -s /bin/bash "$VPS_USER"
  echo "$VPS_USER:$VPS_PASSWORD" | sudo chpasswd
  sudo usermod -aG sudo "$VPS_USER"
  echo "$VPS_USER ALL=(ALL) NOPASSWD:ALL" | sudo tee "/etc/sudoers.d/$VPS_USER" >/dev/null
  sudo chmod 0440 "/etc/sudoers.d/$VPS_USER"
else
  warn "User '$VPS_USER' already exists"
fi

log "Enabling SSH password authentication..."
sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl enable ssh
sudo systemctl restart ssh || sudo systemctl restart sshd || true

log "Cleaning up package caches..."
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

log "Setup complete."

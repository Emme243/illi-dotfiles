#!/usr/bin/env bash
set -Eeuo pipefail

# setup-docker-lazydocker-arch.sh
# Docker Engine + Docker Compose + LazyDocker setup for Arch-based systems.
# No Docker Desktop.

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "Missing required command: $1"
    exit 1
  }
}

if [[ ${EUID} -eq 0 ]]; then
  err "Run this as your normal user, not root. Script will use sudo when needed."
  exit 1
fi

require_cmd sudo
require_cmd pacman
require_cmd systemctl

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  case "${ID:-} ${ID_LIKE:-}" in
    *arch*|*endeavouros*|*manjaro*) ;;
    *) warn "This does not look like Arch/Arch-based Linux. Continuing because pacman exists." ;;
  esac
fi

REAL_USER="${SUDO_USER:-$USER}"

log "Syncing package database"
sudo pacman -Sy --needed --noconfirm archlinux-keyring

log "Installing Docker Engine, Docker Compose, and LazyDocker"
sudo pacman -S --needed --noconfirm docker docker-compose lazydocker

log "Enabling and starting Docker daemon"
sudo systemctl enable --now docker.service

log "Adding '${REAL_USER}' to docker group for sudo-less Docker commands"
if getent group docker >/dev/null 2>&1; then
  sudo usermod -aG docker "${REAL_USER}"
else
  sudo groupadd docker
  sudo usermod -aG docker "${REAL_USER}"
fi

log "Checking Docker service"
sudo systemctl --no-pager --full status docker.service || true

log "Verifying versions"
docker --version || true
docker compose version || true
lazydocker --version || true

log "Testing Docker with hello-world"
if groups "${REAL_USER}" | grep -qE '(^| )docker( |$)' && docker info >/dev/null 2>&1; then
  docker run --rm hello-world
else
  warn "Current shell may not have docker group yet. Testing with sudo."
  sudo docker run --rm hello-world
fi

cat <<'NEXT_STEPS'

Done.

Important next step:
  Log out and log back in, or reboot, so your shell gets docker group access.

After login, test:
  docker info
  docker run --rm hello-world
  lazydocker

Useful commands:
  sudo systemctl status docker
  sudo systemctl restart docker
  docker compose version

Security note:
  Users in docker group effectively get root-level control through Docker.
  Fine for a personal dev laptop. Do not add untrusted users.
NEXT_STEPS

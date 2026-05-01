#!/usr/bin/env bash
set -Eeuo pipefail

# Fully remove local Turntable project setup.
# Scope:
# - Removes ~/projects/turntable repo directory
# - Removes known backup folders created by setup scripts
# - Runs docker compose down -v --remove-orphans from backend compose file when available
# - Removes local /etc/hosts entries for Turntable dev domains
#
# Does NOT:
# - Uninstall Docker, docker compose, lazydocker, mise, Node, uv, Git, SSH config, or system packages
# - Delete any database outside Docker volumes/files managed by this project

PROJECT_PARENT="${PROJECT_PARENT:-$HOME/projects}"
PROJECT_DIR="${PROJECT_DIR:-$PROJECT_PARENT/turntable}"
BACKUP_GLOB_PREFIX="${BACKUP_GLOB_PREFIX:-$PROJECT_PARENT/turntable.}"
HOSTS_FILE="${HOSTS_FILE:-/etc/hosts}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-turntable}"

DRY_RUN=0
FORCE=0
REMOVE_BACKUPS=1
REMOVE_HOSTS=1
REMOVE_DOCKER=1
USE_SUDO_RM=1

log() { printf '\033[1;34m[turntable-remove]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warning]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --force             Do not prompt before deleting
  --dry-run           Print actions without changing anything
  --keep-docker       Do not stop/remove project Docker containers or volumes
  --keep-hosts        Do not edit /etc/hosts
  --keep-backups      Do not remove turntable.* backup folders under ~/projects
  --no-sudo-rm        Do not retry failed directory removal with sudo
  -h, --help          Show this help

Environment overrides:
  PROJECT_DIR=/custom/path/to/turntable
  PROJECT_PARENT=/custom/projects
  COMPOSE_PROJECT_NAME=turntable

Examples:
  ./remove-turntable-project.sh
  ./remove-turntable-project.sh --dry-run
  ./remove-turntable-project.sh --force
USAGE
}

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] %q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

remove_dir() {
  local target="$1"

  if [[ ! -e "$target" ]]; then
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] rm -rf -- '$target'"
    if [[ "$USE_SUDO_RM" -eq 1 ]]; then
      echo "[dry-run] if permission denied: sudo rm -rf -- '$target'"
    fi
    return 0
  fi

  local err_file
  err_file="$(mktemp)"

  if rm -rf -- "$target" 2>"$err_file"; then
    rm -f "$err_file"
    return 0
  fi

  warn "Normal rm failed: $(cat "$err_file")"
  rm -f "$err_file"

  if [[ "$USE_SUDO_RM" -eq 1 ]]; then
    warn "Retrying with sudo because Docker bind-mounted data can create root-owned files."
    sudo rm -rf -- "$target"
  else
    die "Could not remove '$target'. Re-run without --no-sudo-rm or manually fix permissions."
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --keep-docker) REMOVE_DOCKER=0 ;;
    --keep-hosts) REMOVE_HOSTS=0 ;;
    --keep-backups) REMOVE_BACKUPS=0 ;;
    --no-sudo-rm) USE_SUDO_RM=0 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
  shift
done

# Refuse dangerous paths.
case "$PROJECT_DIR" in
  ""|"/"|"$HOME"|"$PROJECT_PARENT")
    die "Unsafe PROJECT_DIR: '$PROJECT_DIR'"
    ;;
esac

log "Target project directory: $PROJECT_DIR"
log "Compose project name: $COMPOSE_PROJECT_NAME"

if [[ "$FORCE" -ne 1 ]]; then
  cat <<CONFIRM

This will remove local Turntable project data:
  - $PROJECT_DIR
  - ${BACKUP_GLOB_PREFIX}* backup folders, unless --keep-backups
  - Docker containers/networks/volumes for compose project '$COMPOSE_PROJECT_NAME', unless --keep-docker
  - Turntable dev hostnames from $HOSTS_FILE, unless --keep-hosts

This cannot be undone.
CONFIRM
  read -r -p "Type REMOVE TURNTABLE to continue: " answer
  [[ "$answer" == "REMOVE TURNTABLE" ]] || die "Aborted."
fi

# Stop/remove project Docker resources before deleting repo, because compose file lives in backend/.
if [[ "$REMOVE_DOCKER" -eq 1 ]]; then
  COMPOSE_DIR="$PROJECT_DIR/backend"
  if [[ -f "$COMPOSE_DIR/docker-compose.yml" || -f "$COMPOSE_DIR/compose.yml" || -f "$COMPOSE_DIR/compose.yaml" ]]; then
    log "Removing project Docker containers, networks, and volumes from $COMPOSE_DIR"
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
      if docker compose version >/dev/null 2>&1; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
          echo "[dry-run] (cd '$COMPOSE_DIR' && COMPOSE_PROJECT_NAME='$COMPOSE_PROJECT_NAME' docker compose down -v --remove-orphans)"
        else
          (cd "$COMPOSE_DIR" && COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" docker compose down -v --remove-orphans)
        fi
      elif command -v docker-compose >/dev/null 2>&1; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
          echo "[dry-run] (cd '$COMPOSE_DIR' && COMPOSE_PROJECT_NAME='$COMPOSE_PROJECT_NAME' docker-compose down -v --remove-orphans)"
        else
          (cd "$COMPOSE_DIR" && COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" docker-compose down -v --remove-orphans)
        fi
      else
        warn "Docker found, but no Docker Compose command found. Skipping Docker cleanup."
      fi
    else
      warn "Docker is unavailable or daemon not reachable. Skipping Docker cleanup."
    fi
  else
    warn "No compose file found under $COMPOSE_DIR. Skipping compose cleanup."
  fi
else
  log "Skipping Docker cleanup."
fi

# Remove repo directory. Docker bind mounts may leave root-owned data under backend/data/db.
if [[ -e "$PROJECT_DIR" ]]; then
  log "Removing project directory: $PROJECT_DIR"
  remove_dir "$PROJECT_DIR"
else
  log "Project directory already absent."
fi

# Remove backups created by previous setup fixes.
if [[ "$REMOVE_BACKUPS" -eq 1 ]]; then
  shopt -s nullglob
  backups=("${BACKUP_GLOB_PREFIX}"*)
  shopt -u nullglob

  if [[ ${#backups[@]} -gt 0 ]]; then
    log "Removing backup folders:"
    for path in "${backups[@]}"; do
      # Only delete directories that are clearly turntable backups.
      if [[ -d "$path" && "$(basename "$path")" == turntable.* ]]; then
        echo "  - $path"
        remove_dir "$path"
      fi
    done
  else
    log "No turntable backup folders found."
  fi
else
  log "Skipping backup folder cleanup."
fi

# Remove hosts entries. Remove whole lines that contain known local Turntable dev hostnames.
if [[ "$REMOVE_HOSTS" -eq 1 ]]; then
  HOST_PAT='(laughfactory|jazztx|chucklehut)\.turntabletix'
  if [[ -f "$HOSTS_FILE" ]] && grep -Eq "$HOST_PAT" "$HOSTS_FILE"; then
    log "Removing Turntable dev host entries from $HOSTS_FILE"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[dry-run] sudo awk '!/$HOST_PAT/' '$HOSTS_FILE' > temp && sudo cp temp '$HOSTS_FILE'"
    else
      tmp_file="$(mktemp)"
      sudo cp "$HOSTS_FILE" "$HOSTS_FILE.bak.turntable-remove"
      sudo awk '!/(laughfactory|jazztx|chucklehut)\.turntabletix/' "$HOSTS_FILE" > "$tmp_file"
      sudo cp "$tmp_file" "$HOSTS_FILE"
      rm -f "$tmp_file"
      log "Backup saved at $HOSTS_FILE.bak.turntable-remove"
    fi
  else
    log "No Turntable dev host entries found."
  fi
else
  log "Skipping /etc/hosts cleanup."
fi

log "Done. Turntable local project removed."

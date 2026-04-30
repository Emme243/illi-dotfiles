#!/usr/bin/env bash
set -Eeuo pipefail

# setup-turntable.sh
# Idempotent local setup for Turntable repo.
# Assumes SSH/GitHub auth already works.
# Assumes Docker engine + Compose are already installed by a separate system script.
# Starts this project's containers from backend/docker-compose.yml.

REPO_SSH="git@github.com:turntabletickets/turntable.git"
PROJECTS_DIR="${HOME}/projects"
REPO_DIR="${PROJECTS_DIR}/turntable"
NODE_VERSION="22"
HOSTS_LINE="127.0.0.1 laughfactory.turntabletix jazztx.turntabletix chucklehut.turntabletix"

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
fail() {
  printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2
  exit 1
}
need_cmd() { command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"; }

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    printf 'docker compose'
  elif command -v docker-compose >/dev/null 2>&1; then
    printf 'docker-compose'
  else
    fail "Missing Docker Compose. Install Docker Compose plugin or legacy docker-compose first."
  fi
}

check_docker_ready() {
  need_cmd docker

  if ! docker info >/dev/null 2>&1; then
    fail "Docker is installed but daemon is not reachable. Start Docker and ensure your user can access it."
  fi

  compose_cmd >/dev/null
}

clone_or_update_repo() {
  mkdir -p "$PROJECTS_DIR"

  if [[ -d "$REPO_DIR/.git" ]]; then
    log "Repo already exists at $REPO_DIR. Fetching latest refs."
    git -C "$REPO_DIR" remote get-url origin >/dev/null 2>&1 || fail "Existing repo has no origin: $REPO_DIR"

    local origin_url
    origin_url="$(git -C "$REPO_DIR" remote get-url origin)"
    if [[ "$origin_url" != "$REPO_SSH" ]]; then
      warn "Existing origin differs: $origin_url"
      warn "Expected: $REPO_SSH"
      warn "Leaving origin unchanged."
    fi

    git -C "$REPO_DIR" fetch --prune origin
    return 0
  fi

  # Common broken state: previous script/user created ~/projects/turntable,
  # then cloned repo inside it as ~/projects/turntable/turntable.
  if [[ -d "$REPO_DIR/turntable/.git" ]]; then
    fail "Nested git repo found at $REPO_DIR/turntable, but expected repo root at $REPO_DIR.

Fix manually:
  mv $REPO_DIR ${REPO_DIR}.nested-backup
  git clone $REPO_SSH $REPO_DIR

Then rerun this script."
  fi

  if [[ -e "$REPO_DIR" ]]; then
    if [[ -z "$(find "$REPO_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
      log "$REPO_DIR exists but is empty. Removing and cloning fresh."
      rmdir "$REPO_DIR"
    else
      local backup_dir
      backup_dir="${REPO_DIR}.non-git-backup.$(date +%Y%m%d-%H%M%S)"
      warn "$REPO_DIR exists but is not a git repo. Moving it to: $backup_dir"
      mv "$REPO_DIR" "$backup_dir"
    fi
  fi

  log "Cloning Turntable repo into $REPO_DIR"
  git clone "$REPO_SSH" "$REPO_DIR"

  [[ -d "$REPO_DIR/.git" ]] || fail "Clone completed, but $REPO_DIR/.git is missing. Something is wrong with clone path."
}

setup_frontend() {
  log "Installing Node.js $NODE_VERSION with mise"
  mise install "node@${NODE_VERSION}"

  log "Installing frontend dependencies"
  [[ -d "$REPO_DIR/frontend" ]] || fail "Missing frontend directory: $REPO_DIR/frontend"
  (
    cd "$REPO_DIR"
    cp .env.sample .env

    cd "$REPO_DIR/frontend"
    mise exec "node@${NODE_VERSION}" -- npm install
  )
}

setup_backend_env() {
  log "Preparing backend"
  [[ -d "$REPO_DIR/backend" ]] || fail "Missing backend directory: $REPO_DIR/backend"

  (
    cd "$REPO_DIR/backend"

    if [[ -f ".env" ]]; then
      log ".env already exists. Keeping it."
    elif [[ -f ".env.sample" ]]; then
      log "Creating .env from .env.sample"
      cp .env.sample .env
      warn "Edit $REPO_DIR/.env with correct local values before running backend."
    else
      warn "No .env or .env.sample found at repo root. Skipping .env creation."
    fi

    log "Installing Python dependencies with uv sync"
    uv sync
  )
}

ensure_hosts_entry() {
  log "Ensuring /etc/hosts contains local Turntable hostnames"

  if grep -Fqx "$HOSTS_LINE" /etc/hosts; then
    log "/etc/hosts entry already exists."
    return 0
  fi

  if grep -Eq '(^|[[:space:]])(laughfactory|jazztx|chucklehut)\.turntabletix([[:space:]]|$)' /etc/hosts; then
    warn "Found existing Turntable-ish hosts entries. Not editing them automatically."
    warn "Expected line: $HOSTS_LINE"
    return 0
  fi

  printf '\n%s\n' "$HOSTS_LINE" | sudo tee -a /etc/hosts >/dev/null
  log "Added hosts entry."
}

setup_project_containers() {
  log "Starting Turntable backend containers"
  [[ -f "$REPO_DIR/backend/docker-compose.yml" ]] || fail "Missing compose file: $REPO_DIR/backend/docker-compose.yml"

  (
    cd "$REPO_DIR/backend"

    local compose
    compose="$(compose_cmd)"

    # shellcheck disable=SC2086 # compose is intentionally split: "docker compose" or "docker-compose".
    $compose up -d
  )
}

run_backend_db_steps() {
  log "Applying migrations"
  (
    cd "$REPO_DIR/backend"
    if ! uv run manage.py migrate; then
      warn "Migrations failed. Most common cause: database containers are not ready yet."
      warn "Check containers with: cd $REPO_DIR/backend && docker compose ps"
      return 0
    fi

    log "Seeding local venues and Site records"
    uv run manage.py shell <<'PYEOF'
from backend.data_utils.makers import mk_venue
from backend.models.Venue import Venue

for name, slug in [("Jazz TX", "jazztx"), ("Laugh Factory", "laughfactory"), ("Chuckle Hut", "chucklehut")]:
    if not Venue.objects.filter(slug=slug).exists():
        v = mk_venue(name, slug=slug)
        print(f"Created '{name}' -> sites: {list(v.sites.values_list('domain', flat=True))}")
    else:
        print(f"'{name}' already exists, skipping.")
PYEOF
  )
}

print_next_steps() {
  cat <<'NEXTEOF'

Done.

Useful checks:

  cd ~/projects/turntable
  git status --short --branch

  cd ~/projects/turntable/backend
  docker compose ps

Next commands, usually in separate terminals:

  cd ~/projects/turntable/frontend
  mise exec node@22 -- npm run serve

  cd ~/projects/turntable
  uv run manage.py runserver

Optional worker:

  cd ~/projects/turntable
  uv run manage.py rqworker --with-scheduler

Browser checks:

  https://localhost:8080/js/chunk-vendors.js
  http://jazztx.turntabletix:8000/api/settings

Stripe webhooks, after installing Stripe CLI:

  stripe listen --forward-to localhost:8000/api/stripe-webhooks/
NEXTEOF
}

main() {
  need_cmd git
  need_cmd mise
  need_cmd uv
  need_cmd sudo
  check_docker_ready

  clone_or_update_repo
  setup_frontend
  setup_backend_env
  ensure_hosts_entry
  setup_project_containers
  run_backend_db_steps
  print_next_steps
}

main "$@"

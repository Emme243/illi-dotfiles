#!/usr/bin/env bash
set -Eeuo pipefail

# setup-github-dev.sh
# Arch-focused setup for:
# - git
# - lazygit
# - GitHub CLI
# - OpenSSH
# - global git identity
# - safe SSH key reuse/generation
# - ssh-agent setup
# - GitHub SSH host config
# - optional repo remote conversion from HTTPS -> SSH
#
# Usage:
#   ./setup-github-dev.sh
#
# Optional env vars:
#   GIT_NAME="Your Name" GIT_EMAIL="you@example.com" GITHUB_USER="youruser" ./setup-github-dev.sh

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
info() { printf "\n==> %s\n" "$*"; }
warn() { printf "\n[WARN] %s\n" "$*" >&2; }
die() { printf "\n[ERROR] %s\n" "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

install_arch_packages() {
  info "Installing packages: git, openssh, github-cli, lazygit"

  if ! need_cmd pacman; then
    die "This script is Arch-focused and expects pacman."
  fi

  sudo pacman -Syu --needed git openssh github-cli lazygit
}

prompt_if_empty() {
  local var_name="$1"
  local prompt="$2"
  local current="${!var_name:-}"

  if [[ -z "$current" ]]; then
    read -rp "$prompt: " current
  fi

  [[ -n "$current" ]] || die "$var_name cannot be empty"
  printf -v "$var_name" '%s' "$current"
}

configure_git_identity() {
  info "Configuring global Git identity"

  GIT_NAME="${GIT_NAME:-$(git config --global user.name || true)}"
  GIT_EMAIL="${GIT_EMAIL:-$(git config --global user.email || true)}"

  prompt_if_empty GIT_NAME "Git user.name"
  prompt_if_empty GIT_EMAIL "Git user.email"

  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
  git config --global init.defaultBranch main
  git config --global pull.rebase false
  git config --global push.autoSetupRemote true

  bold "Git identity:"
  git config --global --get user.name
  git config --global --get user.email
}

find_existing_github_key() {
  # Prefer existing ed25519 keys that look GitHub-related.
  local candidates=(
    "$HOME/.ssh/id_ed25519_github"
    "$HOME/.ssh/github_ed25519"
    "$HOME/.ssh/id_ed25519"
  )

  for key in "${candidates[@]}"; do
    if [[ -f "$key" && -f "$key.pub" ]]; then
      printf "%s" "$key"
      return 0
    fi
  done

  # Fallback: any private key with public pair.
  local key
  shopt -s nullglob
  for pub in "$HOME"/.ssh/*.pub; do
    key="${pub%.pub}"
    if [[ -f "$key" ]]; then
      printf "%s" "$key"
      return 0
    fi
  done
  shopt -u nullglob

  return 1
}

ensure_ssh_key() {
  info "Checking SSH key"

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  local existing_key=""
  if existing_key="$(find_existing_github_key)"; then
    SSH_KEY="$existing_key"
    bold "Reusing existing SSH key:"
    printf "%s\n" "$SSH_KEY"
  else
    SSH_KEY="$HOME/.ssh/id_ed25519_github"

    if [[ -e "$SSH_KEY" || -e "$SSH_KEY.pub" ]]; then
      die "Partial key exists at $SSH_KEY. Check ~/.ssh before continuing."
    fi

    info "No usable key found. Generating new ed25519 key"
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY"
  fi

  chmod 600 "$SSH_KEY"
  chmod 644 "$SSH_KEY.pub"
}

ensure_ssh_agent() {
  info "Starting ssh-agent and loading key"

  if [[ -z "${SSH_AUTH_SOCK:-}" ]] || ! ssh-add -l >/dev/null 2>&1; then
    eval "$(ssh-agent -s)" >/dev/null
  fi

  if ! ssh-add -l 2>/dev/null | grep -q "$(ssh-keygen -lf "$SSH_KEY.pub" | awk '{print $2}')"; then
    ssh-add "$SSH_KEY"
  fi
}

configure_ssh_for_github() {
  info "Configuring ~/.ssh/config for GitHub"

  touch "$HOME/.ssh/config"
  chmod 600 "$HOME/.ssh/config"

  if ! grep -qE '^Host github.com$' "$HOME/.ssh/config"; then
    cat >> "$HOME/.ssh/config" <<EOF

Host github.com
  HostName github.com
  User git
  IdentityFile $SSH_KEY
  IdentitiesOnly yes
  AddKeysToAgent yes
EOF
  else
    warn "~/.ssh/config already has Host github.com. Not overwriting it."
    warn "Make sure it points to: IdentityFile $SSH_KEY"
  fi

  ssh-keyscan github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
  sort -u "$HOME/.ssh/known_hosts" -o "$HOME/.ssh/known_hosts"
  chmod 644 "$HOME/.ssh/known_hosts"
}

maybe_configure_gh() {
  info "Checking GitHub CLI"

  if gh auth status >/dev/null 2>&1; then
    bold "gh already authenticated."
    return 0
  fi

  warn "gh is installed but not authenticated."
  warn "After adding SSH key to GitHub, you can run:"
  printf "  gh auth login\n"
  printf "  gh auth setup-git\n"
}

maybe_convert_current_repo_remote() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi

  local remote
  remote="$(git remote get-url origin 2>/dev/null || true)"

  [[ -n "$remote" ]] || return 0

  if [[ "$remote" =~ ^https://github\.com/([^/]+)/([^/]+)(\.git)?$ ]]; then
    local owner="${BASH_REMATCH[1]}"
    local repo="${BASH_REMATCH[2]}"
    repo="${repo%.git}"

    info "Current repo uses HTTPS origin. Converting to SSH"
    git remote set-url origin "git@github.com:${owner}/${repo}.git"

    bold "New origin:"
    git remote -v
  fi
}

print_public_key_and_next_steps() {
  info "Public SSH key"

  bold "Copy this whole line into GitHub:"
  printf "\n%s\n\n" "$(cat "$SSH_KEY.pub")"

  bold "GitHub path:"
  printf "GitHub → Settings → SSH and GPG keys → New SSH key\n\n"

  bold "After pasting key, test:"
  printf "ssh -T git@github.com\n\n"

  bold "Expected:"
  printf "Hi <username>! You've successfully authenticated, but GitHub does not provide shell access.\n\n"

  bold "Then push:"
  printf "git push -u origin main\n"
}

main() {
  install_arch_packages
  configure_git_identity
  ensure_ssh_key
  ensure_ssh_agent
  configure_ssh_for_github
  maybe_configure_gh
  maybe_convert_current_repo_remote
  print_public_key_and_next_steps
}

main "$@"

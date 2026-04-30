#!/usr/bin/env bash
set -euo pipefail

# install-mise-devtools.sh
# Arch Linux setup for mise + Node/npm + Python + uv
# Safe to run multiple times.

MISE_BIN="$HOME/.local/bin/mise"
MISE_SHIMS="$HOME/.local/share/mise/shims"

log() {
  printf "\n==> %s\n" "$*"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

append_once() {
  local file="$1"
  local marker="$2"
  local content="$3"

  mkdir -p "$(dirname "$file")"
  touch "$file"

  if ! grep -Fq "$marker" "$file"; then
    {
      printf "\n%s\n" "$marker"
      printf "%s\n" "$content"
    } >>"$file"
  fi
}

log "Installing base packages"
sudo pacman -Syu --needed --noconfirm \
  curl git unzip tar gzip xz zstd \
  base-devel \
  bash zsh fish

log "Installing mise"
if has_cmd mise; then
  MISE_CMD="$(command -v mise)"
elif [[ -x "$MISE_BIN" ]]; then
  MISE_CMD="$MISE_BIN"
else
  curl https://mise.run | sh
  MISE_CMD="$MISE_BIN"
fi

log "mise version"
"$MISE_CMD" --version

log "Configuring shell activation"

append_once "$HOME/.bashrc" \
  "# >>> mise setup >>>" \
  'eval "$($HOME/.local/bin/mise activate bash)"'

append_once "${ZDOTDIR:-$HOME}/.zshrc" \
  "# >>> mise setup >>>" \
  'eval "$($HOME/.local/bin/mise activate zsh)"'

append_once "$HOME/.config/fish/config.fish" \
  "# >>> mise setup >>>" \
  '$HOME/.local/bin/mise activate fish | source'

log "Adding mise shims to profile paths for IDEs/scripts"

append_once "$HOME/.profile" \
  "# >>> mise shims >>>" \
  'export PATH="$HOME/.local/share/mise/shims:$PATH"'

append_once "$HOME/.zprofile" \
  "# >>> mise shims >>>" \
  'export PATH="$HOME/.local/share/mise/shims:$PATH"'

append_once "$HOME/.config/fish/config.fish" \
  "# >>> mise shims >>>" \
  'fish_add_path -m $HOME/.local/share/mise/shims'

log "Installing global tools with mise"
"$MISE_CMD" use --global node@latest
"$MISE_CMD" use --global python@latest
"$MISE_CMD" use --global uv@latest

log "Refreshing mise shims"
"$MISE_CMD" reshim || true

log "Versions"
"$MISE_CMD" exec -- node -v
"$MISE_CMD" exec -- npm -v
"$MISE_CMD" exec -- python --version
"$MISE_CMD" exec -- uv --version

cat <<EOF

Done.

Restart terminal, then test:

  which node
  which npm
  which python
  which uv

Expected via mise:

  $MISE_SHIMS/node
  $MISE_SHIMS/npm
  $MISE_SHIMS/python
  $MISE_SHIMS/uv

Run doctor:

  mise doctor

Install other node versions:

  mise install node@20
  mise install node@22
  mise install node@24
  mise ls node # List local node versions

Nvm Mental Model

  nvm install 20              -> mise install node@20
  nvm use 20                  -> mise use node@20
  nvm alias default 22        -> mise use --global node@22
  nvm exec 20 npm test        -> mise exec node@20 -- npm test
  .nvmrc                      -> supported, but mise.toml preferred
EOF

#!/usr/bin/env bash
set -euo pipefail

CUSTOM_KEYBINDS="$HOME/.config/hypr/custom/keybinds.conf"

SCRIPT_CANDIDATES=(
  "$HOME/.config/hypr/hyprland/scripts/workspace_action.sh"
  "$HOME/.config/hypr/illogical-impulse/scripts/workspace_action.sh"
)

WORKSPACE_SCRIPT=""

for candidate in "${SCRIPT_CANDIDATES[@]}"; do
  if [[ -x "$candidate" || -f "$candidate" ]]; then
    WORKSPACE_SCRIPT="$candidate"
    break
  fi
done

if [[ -z "$WORKSPACE_SCRIPT" ]]; then
  echo "ERROR: Could not find workspace_action.sh"
  echo "Checked:"
  printf '  %s\n' "${SCRIPT_CANDIDATES[@]}"
  exit 1
fi

mkdir -p "$(dirname "$CUSTOM_KEYBINDS")"
touch "$CUSTOM_KEYBINDS"

BACKUP="$CUSTOM_KEYBINDS.bak.before-illi-follow-moved-window"

if [[ ! -f "$BACKUP" ]]; then
  cp "$CUSTOM_KEYBINDS" "$BACKUP"
  echo "Backup created: $BACKUP"
else
  echo "Backup already exists: $BACKUP"
fi

START_MARKER="# >>> illi-follow-moved-window >>>"
END_MARKER="# <<< illi-follow-moved-window <<<"

TMP_FILE="$(mktemp)"

# Remove previous managed block.
awk -v start="$START_MARKER" -v end="$END_MARKER" '
  $0 == start { skip = 1; next }
  $0 == end { skip = 0; next }
  !skip { print }
' "$CUSTOM_KEYBINDS" >"$TMP_FILE"

cat >>"$TMP_FILE" <<EOF

$START_MARKER
# Managed by ~/illi-follow-moved-window.sh
# Replaces Illi Super+Alt+number behavior:
# move focused window to workspace, then switch/follow to that workspace.

unbind = SUPER ALT, code:10
bind = SUPER ALT, code:10, exec, bash -lc '"$WORKSPACE_SCRIPT" movetoworkspacesilent 1; "$WORKSPACE_SCRIPT" workspace 1'

unbind = SUPER ALT, code:11
bind = SUPER ALT, code:11, exec, bash -lc '"$WORKSPACE_SCRIPT" movetoworkspacesilent 2; "$WORKSPACE_SCRIPT" workspace 2'

unbind = SUPER ALT, code:12
bind = SUPER ALT, code:12, exec, bash -lc '"$WORKSPACE_SCRIPT" movetoworkspacesilent 3; "$WORKSPACE_SCRIPT" workspace 3'

unbind = SUPER ALT, code:13
bind = SUPER ALT, code:13, exec, bash -lc '"$WORKSPACE_SCRIPT" movetoworkspacesilent 4; "$WORKSPACE_SCRIPT" workspace 4'

unbind = SUPER ALT, code:14
bind = SUPER ALT, code:14, exec, bash -lc '"$WORKSPACE_SCRIPT" movetoworkspacesilent 5; "$WORKSPACE_SCRIPT" workspace 5'

unbind = SUPER ALT, code:15
bind = SUPER ALT, code:15, exec, bash -lc '"$WORKSPACE_SCRIPT" movetoworkspacesilent 6; "$WORKSPACE_SCRIPT" workspace 6'

unbind = SUPER ALT, code:16
bind = SUPER ALT, code:16, exec, bash -lc '"$WORKSPACE_SCRIPT" movetoworkspacesilent 7; "$WORKSPACE_SCRIPT" workspace 7'

unbind = SUPER ALT, code:17
bind = SUPER ALT, code:17, exec, bash -lc '"$WORKSPACE_SCRIPT" movetoworkspacesilent 8; "$WORKSPACE_SCRIPT" workspace 8'

unbind = SUPER ALT, code:18
bind = SUPER ALT, code:18, exec, bash -lc '"$WORKSPACE_SCRIPT" movetoworkspacesilent 9; "$WORKSPACE_SCRIPT" workspace 9'

unbind = SUPER ALT, code:19
bind = SUPER ALT, code:19, exec, bash -lc '"$WORKSPACE_SCRIPT" movetoworkspacesilent 10; "$WORKSPACE_SCRIPT" workspace 10'
$END_MARKER
EOF

mv "$TMP_FILE" "$CUSTOM_KEYBINDS"

if command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  hyprctl reload
  echo "Hyprland reloaded."
else
  echo "Not inside Hyprland or hyprctl missing. Reload manually later with: hyprctl reload"
fi

echo "Done."
echo "Using workspace script: $WORKSPACE_SCRIPT"
echo "Edited: $CUSTOM_KEYBINDS"

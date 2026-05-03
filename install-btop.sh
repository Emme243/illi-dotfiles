#!/usr/bin/env bash
set -euo pipefail

# install-btop-matugen.sh
# Arch/Illi/Hyprland friendly.
# Installs btop + matugen, creates btop matugen theme template,
# patches matugen config idempotently, sets btop to use generated theme.

THEME_NAME="matugen"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

BTOP_DIR="$XDG_CONFIG_HOME/btop"
BTOP_THEMES_DIR="$BTOP_DIR/themes"
BTOP_CONF="$BTOP_DIR/btop.conf"
BTOP_THEME_OUT="$BTOP_THEMES_DIR/${THEME_NAME}.theme"

MATUGEN_DIR="$XDG_CONFIG_HOME/matugen"
MATUGEN_CONF="$MATUGEN_DIR/config.toml"
MATUGEN_TEMPLATE_DIR="$MATUGEN_DIR/templates"
MATUGEN_BTOP_TEMPLATE="$MATUGEN_TEMPLATE_DIR/btop.theme"

START_MARKER="# >>> btop matugen theme"
END_MARKER="# <<< btop matugen theme"

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

install_packages() {
  if need_cmd pacman; then
    sudo pacman -S --needed btop matugen
  elif need_cmd paru; then
    paru -S --needed btop matugen
  elif need_cmd yay; then
    yay -S --needed btop matugen
  else
    echo "No pacman/paru/yay found. Install btop + matugen manually, then rerun."
    exit 1
  fi
}

backup_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  cp -n "$file" "${file}.bak" 2>/dev/null || true
}

write_btop_template() {
  mkdir -p "$MATUGEN_TEMPLATE_DIR" "$BTOP_THEMES_DIR"

  cat >"$MATUGEN_BTOP_TEMPLATE" <<'EOF'
# Matugen generated btop theme
# Do not edit generated output. Edit ~/.config/matugen/templates/btop.theme instead.

theme[main_bg]="{{colors.surface.default.hex}}"
theme[main_fg]="{{colors.on_surface.default.hex}}"
theme[title]="{{colors.primary.default.hex}}"
theme[hi_fg]="{{colors.primary.default.hex}}"
theme[selected_bg]="{{colors.surface_container_high.default.hex}}"
theme[selected_fg]="{{colors.on_surface.default.hex}}"
theme[inactive_fg]="{{colors.outline.default.hex}}"

theme[proc_misc]="{{colors.secondary.default.hex}}"

theme[cpu_box]="{{colors.primary.default.hex}}"
theme[mem_box]="{{colors.secondary.default.hex}}"
theme[net_box]="{{colors.tertiary.default.hex}}"
theme[proc_box]="{{colors.primary_container.default.hex}}"

theme[div_line]="{{colors.outline_variant.default.hex}}"

theme[temp_start]="{{colors.primary.default.hex}}"
theme[temp_mid]="{{colors.tertiary.default.hex}}"
theme[temp_end]="{{colors.error.default.hex}}"

theme[cpu_start]="{{colors.primary.default.hex}}"
theme[cpu_mid]="{{colors.secondary.default.hex}}"
theme[cpu_end]="{{colors.tertiary.default.hex}}"

theme[free_start]="{{colors.secondary.default.hex}}"
theme[free_mid]="{{colors.primary.default.hex}}"
theme[free_end]="{{colors.tertiary.default.hex}}"

theme[cached_start]="{{colors.surface_container_highest.default.hex}}"
theme[cached_mid]="{{colors.secondary_container.default.hex}}"
theme[cached_end]="{{colors.secondary.default.hex}}"

theme[available_start]="{{colors.primary_container.default.hex}}"
theme[available_mid]="{{colors.primary.default.hex}}"
theme[available_end]="{{colors.tertiary.default.hex}}"

theme[used_start]="{{colors.tertiary.default.hex}}"
theme[used_mid]="{{colors.error_container.default.hex}}"
theme[used_end]="{{colors.error.default.hex}}"

theme[download_start]="{{colors.primary.default.hex}}"
theme[download_mid]="{{colors.secondary.default.hex}}"
theme[download_end]="{{colors.tertiary.default.hex}}"

theme[upload_start]="{{colors.tertiary.default.hex}}"
theme[upload_mid]="{{colors.secondary.default.hex}}"
theme[upload_end]="{{colors.primary.default.hex}}"

theme[process_start]="{{colors.primary.default.hex}}"
theme[process_mid]="{{colors.secondary.default.hex}}"
theme[process_end]="{{colors.error.default.hex}}"

theme[proc_pause_bg]="{{colors.error_container.default.hex}}"
theme[proc_follow_bg]="{{colors.secondary_container.default.hex}}"
theme[proc_banner_bg]="{{colors.primary_container.default.hex}}"
theme[proc_banner_fg]="{{colors.on_primary_container.default.hex}}"

theme[followed_bg]="{{colors.secondary_container.default.hex}}"
theme[followed_fg]="{{colors.on_secondary_container.default.hex}}"
EOF
}

patch_matugen_config() {
  mkdir -p "$MATUGEN_DIR"
  touch "$MATUGEN_CONF"
  backup_file "$MATUGEN_CONF"

  # Remove old managed block, then append fresh block.
  awk -v start="$START_MARKER" -v end="$END_MARKER" '
    $0 == start { skip=1; next }
    $0 == end { skip=0; next }
    skip != 1 { print }
  ' "$MATUGEN_CONF" >"${MATUGEN_CONF}.tmp"

  cat >>"${MATUGEN_CONF}.tmp" <<EOF

$START_MARKER
[templates.btop]
input_path = "$MATUGEN_BTOP_TEMPLATE"
output_path = "$BTOP_THEME_OUT"
$END_MARKER
EOF

  mv "${MATUGEN_CONF}.tmp" "$MATUGEN_CONF"
}

patch_btop_config() {
  mkdir -p "$BTOP_DIR"
  touch "$BTOP_CONF"
  backup_file "$BTOP_CONF"

  if grep -qE '^color_theme[[:space:]]*=' "$BTOP_CONF"; then
    sed -i "s|^color_theme[[:space:]]*=.*|color_theme = \"$THEME_NAME\"|" "$BTOP_CONF"
  else
    printf '\ncolor_theme = "%s"\n' "$THEME_NAME" >>"$BTOP_CONF"
  fi

  if grep -qE '^theme_background[[:space:]]*=' "$BTOP_CONF"; then
    sed -i 's|^theme_background[[:space:]]*=.*|theme_background = true|' "$BTOP_CONF"
  else
    printf 'theme_background = true\n' >>"$BTOP_CONF"
  fi

  if grep -qE '^truecolor[[:space:]]*=' "$BTOP_CONF"; then
    sed -i 's|^truecolor[[:space:]]*=.*|truecolor = true|' "$BTOP_CONF"
  else
    printf 'truecolor = true\n' >>"$BTOP_CONF"
  fi
}

generate_now_if_possible() {
  # Try Illi-ish / Hyprland-ish common wallpaper files.
  local candidates=(
    "$HOME/.cache/current_wallpaper"
    "$HOME/.cache/ags/user/generated/wallpaper/path.txt"
    "$HOME/.config/hypr/wallpaper_effects/.wallpaper_current"
    "$HOME/.local/state/wallpaper/current"
  )

  local wall=""
  for candidate in "${candidates[@]}"; do
    [[ -f "$candidate" ]] || continue

    # Candidate may be image itself or file containing image path.
    if file --mime-type "$candidate" 2>/dev/null | grep -q 'image/'; then
      wall="$candidate"
      break
    fi

    local maybe
    maybe="$(head -n1 "$candidate" | sed 's/^file:\/\///' | xargs)"
    if [[ -f "$maybe" ]]; then
      wall="$maybe"
      break
    fi
  done

  if [[ -n "$wall" ]]; then
    matugen image "$wall" >/dev/null
    echo "Generated btop theme from: $wall"
  else
    cat >"$BTOP_THEME_OUT" <<'EOF'
# Fallback matugen btop theme.
# This will be overwritten next time matugen runs from wallpaper.
theme[main_bg]="#11111b"
theme[main_fg]="#cdd6f4"
theme[title]="#cba6f7"
theme[hi_fg]="#cba6f7"
theme[selected_bg]="#313244"
theme[selected_fg]="#cdd6f4"
theme[inactive_fg]="#7f849c"
theme[proc_misc]="#89b4fa"
theme[cpu_box]="#cba6f7"
theme[mem_box]="#89b4fa"
theme[net_box]="#a6e3a1"
theme[proc_box]="#f5c2e7"
theme[div_line]="#45475a"
theme[temp_start]="#a6e3a1"
theme[temp_mid]="#f9e2af"
theme[temp_end]="#f38ba8"
theme[cpu_start]="#89b4fa"
theme[cpu_mid]="#cba6f7"
theme[cpu_end]="#f5c2e7"
theme[free_start]="#a6e3a1"
theme[free_mid]="#89b4fa"
theme[free_end]="#cba6f7"
theme[cached_start]="#45475a"
theme[cached_mid]="#585b70"
theme[cached_end]="#89b4fa"
theme[available_start]="#89b4fa"
theme[available_mid]="#a6e3a1"
theme[available_end]="#cba6f7"
theme[used_start]="#f9e2af"
theme[used_mid]="#fab387"
theme[used_end]="#f38ba8"
theme[download_start]="#89b4fa"
theme[download_mid]="#a6e3a1"
theme[download_end]="#cba6f7"
theme[upload_start]="#f5c2e7"
theme[upload_mid]="#cba6f7"
theme[upload_end]="#89b4fa"
theme[process_start]="#89b4fa"
theme[process_mid]="#cba6f7"
theme[process_end]="#f38ba8"
theme[proc_pause_bg]="#f38ba8"
theme[proc_follow_bg]="#313244"
theme[proc_banner_bg]="#45475a"
theme[proc_banner_fg]="#cdd6f4"
theme[followed_bg]="#313244"
theme[followed_fg]="#cdd6f4"
EOF
    echo "No current wallpaper path found. Wrote fallback theme."
    echo "Next wallpaper change through matugen should overwrite it."
  fi
}

main() {
  install_packages
  write_btop_template
  patch_matugen_config
  patch_btop_config
  generate_now_if_possible

  echo
  echo "Done."
  echo "btop theme: $BTOP_THEME_OUT"
  echo "matugen template: $MATUGEN_BTOP_TEMPLATE"
  echo "matugen config patched: $MATUGEN_CONF"
  echo
  echo "Run: btop"
}

main "$@"

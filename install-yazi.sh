#!/usr/bin/env bash
set -euo pipefail

# Yazi + Illogical Impulse / matugen theme setup
# Arch / Omarchy focused.

YAZI_DIR="$HOME/.config/yazi"
MATUGEN_DIR="$HOME/.config/matugen"
MATUGEN_CONFIG="$MATUGEN_DIR/config.toml"
YAZI_TEMPLATE="$MATUGEN_DIR/templates/yazi-theme.toml"

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

install_arch_packages() {
  if ! need_cmd pacman; then
    echo "pacman not found. This script targets Arch/Omarchy."
    exit 1
  fi

  echo "Installing yazi + dependencies..."
  sudo pacman -S --needed \
    yazi \
    matugen \
    ffmpeg \
    7zip \
    jq \
    poppler \
    fd \
    ripgrep \
    fzf \
    zoxide \
    resvg \
    imagemagick \
    wl-clipboard
}

backup_file() {
  local file="$1"

  if [[ -f "$file" ]]; then
    cp "$file" "$file.bak.$(date +%Y%m%d-%H%M%S)"
  fi
}

write_yazi_template() {
  mkdir -p "$YAZI_DIR" "$MATUGEN_DIR/templates"

  backup_file "$YAZI_TEMPLATE"

  cat > "$YAZI_TEMPLATE" <<'EOF'
"$schema" = "https://yazi-rs.github.io/schemas/theme.json"

[app]
overall = { bg = "{{colors.background.default.hex}}" }

[mgr]
cwd = { fg = "{{colors.primary.default.hex}}", bold = true }

find_keyword  = { fg = "{{colors.primary.default.hex}}", bold = true }
find_position = { fg = "{{colors.tertiary.default.hex}}", bold = true }

marker_copied   = { fg = "{{colors.primary.default.hex}}", bg = "{{colors.primary_container.default.hex}}" }
marker_cut      = { fg = "{{colors.error.default.hex}}", bg = "{{colors.error_container.default.hex}}" }
marker_marked   = { fg = "{{colors.tertiary.default.hex}}", bg = "{{colors.tertiary_container.default.hex}}" }
marker_selected = { fg = "{{colors.secondary.default.hex}}", bg = "{{colors.secondary_container.default.hex}}" }

count_copied   = { fg = "{{colors.on_primary.default.hex}}", bg = "{{colors.primary.default.hex}}" }
count_cut      = { fg = "{{colors.on_error.default.hex}}", bg = "{{colors.error.default.hex}}" }
count_selected = { fg = "{{colors.on_secondary.default.hex}}", bg = "{{colors.secondary.default.hex}}" }

border_symbol = "│"
border_style  = { fg = "{{colors.outline_variant.default.hex}}", dim = true }

[indicator]
# Left pane: subtle
parent = { bg = "{{colors.surface_container_low.default.hex}}" }

# Middle pane: real selected item
current = { fg = "{{colors.on_primary_container.default.hex}}", bg = "{{colors.primary_container.default.hex}}", bold = true }

# Right pane: subtle preview cursor
preview = { bg = "{{colors.surface_container_low.default.hex}}" }

padding = { open = " ", close = " " }

[mode]
normal_main = { fg = "{{colors.on_primary.default.hex}}", bg = "{{colors.primary.default.hex}}", bold = true }
normal_alt  = { fg = "{{colors.on_surface.default.hex}}", bg = "{{colors.surface_container_high.default.hex}}" }

select_main = { fg = "{{colors.on_secondary.default.hex}}", bg = "{{colors.secondary.default.hex}}", bold = true }
select_alt  = { fg = "{{colors.on_surface.default.hex}}", bg = "{{colors.surface_container_high.default.hex}}" }

unset_main = { fg = "{{colors.on_error.default.hex}}", bg = "{{colors.error.default.hex}}", bold = true }
unset_alt  = { fg = "{{colors.on_surface.default.hex}}", bg = "{{colors.surface_container_high.default.hex}}" }

[status]
overall = { fg = "{{colors.on_surface.default.hex}}", bg = "{{colors.surface_container.default.hex}}" }

sep_left  = { open = "", close = "" }
sep_right = { open = "", close = "" }

perm_type  = { fg = "{{colors.on_surface.default.hex}}" }
perm_read  = { fg = "{{colors.primary.default.hex}}" }
perm_write = { fg = "{{colors.secondary.default.hex}}" }
perm_exec  = { fg = "{{colors.tertiary.default.hex}}" }
perm_sep   = { fg = "{{colors.outline.default.hex}}", dim = true }

progress_label  = { fg = "{{colors.on_surface.default.hex}}", bold = true }
progress_normal = { fg = "{{colors.primary.default.hex}}", bg = "{{colors.surface_container_high.default.hex}}" }
progress_error  = { fg = "{{colors.error.default.hex}}", bg = "{{colors.error_container.default.hex}}" }

[input]
border   = { fg = "{{colors.primary.default.hex}}" }
title    = { fg = "{{colors.primary.default.hex}}", bold = true }
value    = { fg = "{{colors.on_surface.default.hex}}" }
selected = { bg = "{{colors.primary_container.default.hex}}" }

[select]
border = { fg = "{{colors.primary.default.hex}}" }
active = { fg = "{{colors.primary.default.hex}}", bold = true }

[tasks]
border  = { fg = "{{colors.primary.default.hex}}" }
title   = { fg = "{{colors.primary.default.hex}}", bold = true }
hovered = { fg = "{{colors.on_primary_container.default.hex}}", bg = "{{colors.primary_container.default.hex}}" }

[which]
mask            = { bg = "{{colors.background.default.hex}}" }
cand            = { fg = "{{colors.primary.default.hex}}" }
rest            = { fg = "{{colors.outline.default.hex}}" }
desc            = { fg = "{{colors.on_surface.default.hex}}" }
separator       = "  "
separator_style = { fg = "{{colors.outline.default.hex}}", dim = true }

[help]
on      = { fg = "{{colors.primary.default.hex}}", bold = true }
run     = { fg = "{{colors.secondary.default.hex}}" }
desc    = { fg = "{{colors.on_surface.default.hex}}" }
hovered = { fg = "{{colors.on_primary_container.default.hex}}", bg = "{{colors.primary_container.default.hex}}" }

[filetype]
rules = [
  { mime = "image/*", fg = "{{colors.primary.default.hex}}" },
  { mime = "video/*", fg = "{{colors.tertiary.default.hex}}" },
  { mime = "audio/*", fg = "{{colors.secondary.default.hex}}" },

  { mime = "application/zip", fg = "{{colors.error.default.hex}}" },
  { mime = "application/gzip", fg = "{{colors.error.default.hex}}" },
  { mime = "application/x-tar", fg = "{{colors.error.default.hex}}" },

  { name = "*/", fg = "{{colors.primary.default.hex}}", bold = true },
]
EOF

  echo "Wrote: $YAZI_TEMPLATE"
}

patch_matugen_config() {
  mkdir -p "$MATUGEN_DIR"

  if [[ ! -f "$MATUGEN_CONFIG" ]]; then
    touch "$MATUGEN_CONFIG"
  fi

  backup_file "$MATUGEN_CONFIG"

  local tmp
  tmp="$(mktemp)"

  # Remove old [templates.yazi] block, if any.
  awk '
    /^\[templates\.yazi\]/ { skip=1; next }
    /^\[/ && skip==1 { skip=0 }
    skip!=1 { print }
  ' "$MATUGEN_CONFIG" > "$tmp"

  cat >> "$tmp" <<EOF

[templates.yazi]
input_path = "~/.config/matugen/templates/yazi-theme.toml"
output_path = "~/.config/yazi/theme.toml"
EOF

  mv "$tmp" "$MATUGEN_CONFIG"

  echo "Patched: $MATUGEN_CONFIG"
}

generate_once_if_possible() {
  local wallpaper_dir=""

  for dir in \
    "$HOME/Pictures/wallpapers" \
    "$HOME/Pictures/Wallpapers" \
    "$HOME/wallpapers" \
    "$HOME/Wallpapers" \
    "$HOME/.config/backgrounds" \
    "$HOME/.local/share/backgrounds"
  do
    if [[ -d "$dir" ]]; then
      wallpaper_dir="$dir"
      break
    fi
  done

  if [[ -z "$wallpaper_dir" ]]; then
    echo "No wallpaper dir found. Skipping first generation."
    echo "Later, change wallpaper through illi, or run:"
    echo "  matugen image /path/to/wallpaper.jpg"
    return 0
  fi

  local wallpaper=""

  # Avoid `find | head` because pipefail can kill script.
  while IFS= read -r -d '' file; do
    wallpaper="$file"
    break
  done < <(
    find "$wallpaper_dir" -maxdepth 1 -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
      -print0
  )

  if [[ -z "$wallpaper" ]]; then
    echo "No image found in: $wallpaper_dir"
    echo "Later run:"
    echo "  matugen image /path/to/wallpaper.jpg"
    return 0
  fi

  echo "Generating first Yazi theme from:"
  echo "  $wallpaper"

  if ! matugen image "$wallpaper"; then
    echo "matugen generation failed."
    echo "Try manually:"
    echo "  matugen image \"$wallpaper\""
    return 1
  fi
}

validate_yazi_theme() {
  if [[ ! -f "$YAZI_DIR/theme.toml" ]]; then
    echo "theme.toml not generated yet."
    return 0
  fi

  if grep -q '{{colors\.' "$YAZI_DIR/theme.toml"; then
    echo "Generated theme still contains raw matugen placeholders."
    echo "That means matugen did not process the template."
    exit 1
  fi

  echo "Yazi theme generated:"
  echo "  $YAZI_DIR/theme.toml"
}

main() {
  install_arch_packages

  if ! need_cmd yazi; then
    echo "yazi install failed or not in PATH."
    exit 1
  fi

  if ! need_cmd matugen; then
    echo "matugen install failed or not in PATH."
    exit 1
  fi

  write_yazi_template
  patch_matugen_config
  generate_once_if_possible
  validate_yazi_theme

  echo
  echo "Done."
  echo "Open with:"
  echo "  yazi"
  echo
  echo "When illi changes wallpaper/theme, matugen should regenerate:"
  echo "  ~/.config/yazi/theme.toml"
}

main "$@"

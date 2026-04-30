#!/usr/bin/env bash
# legion-arch-workstation-tune-fixed.sh
#
# Arch laptop setup for workstation performance + idle efficiency.
#
# Fixed:
#   - nvidia-open-dkms vs nvidia-open-lts conflict
#   - linux-lts installed without linux-lts-headers
#   - DKMS rebuild before mkinitcpio
#   - helper scripts still get installed even if NVIDIA initramfs has issues
#   - jack2 vs pipewire-jack conflict
#
# Run:
#   chmod +x legion-arch-workstation-tune-fixed.sh
#   sudo ./legion-arch-workstation-tune-fixed.sh
#
# Optional:
#   sudo ./legion-arch-workstation-tune-fixed.sh --with-legion
#   sudo ./legion-arch-workstation-tune-fixed.sh --skip-nvidia
#   sudo ./legion-arch-workstation-tune-fixed.sh --no-lts
#   sudo ./legion-arch-workstation-tune-fixed.sh --dry-run

set -Eeuo pipefail

WITH_LEGION=0
SKIP_NVIDIA=0
NO_LTS=0
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --with-legion) WITH_LEGION=1 ;;
    --skip-nvidia) SKIP_NVIDIA=1 ;;
    --no-lts) NO_LTS=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      sed -n '1,90p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

log() {
  printf '\n\033[1;34m==>\033[0m %s\n' "$*"
}

warn() {
  printf '\n\033[1;33mWARNING:\033[0m %s\n' "$*" >&2
}

die() {
  printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2
  exit 1
}

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] %q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

need_root() {
  [[ "${EUID}" -eq 0 ]] || die "Run as root: sudo $0"
}

need_arch() {
  [[ -f /etc/arch-release ]] || die "This script is for Arch Linux only."
  command -v pacman >/dev/null 2>&1 || die "pacman not found."
}

backup_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    local backup="${file}.bak.$(date +%Y%m%d-%H%M%S)"
    log "Backing up $file -> $backup"
    run cp -a "$file" "$backup"
  fi
}

repo_has() {
  pacman -Si "$1" >/dev/null 2>&1
}

installed_has() {
  pacman -Q "$1" >/dev/null 2>&1
}

kernel_pkg_installed() {
  pacman -Q "$1" >/dev/null 2>&1
}

has_nvidia() {
  lspci 2>/dev/null | grep -iq nvidia
}

detect_cpu_vendor() {
  if grep -qi 'AuthenticAMD' /proc/cpuinfo; then
    echo "amd"
  elif grep -qi 'GenuineIntel' /proc/cpuinfo; then
    echo "intel"
  else
    echo "unknown"
  fi
}

append_unique_pkg() {
  local pkg="$1"
  local existing
  for existing in "${pkgs[@]}"; do
    [[ "$existing" == "$pkg" ]] && return 0
  done
  pkgs+=("$pkg")
}

install_packages() {
  local -a packages=("$@")
  [[ "${#packages[@]}" -eq 0 ]] && return 0

  log "Installing packages"
  run pacman -Syu --needed --noconfirm "${packages[@]}"
}

enable_service_if_exists() {
  local unit="$1"

  if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
    log "Enabling $unit"
    run systemctl enable --now "$unit" || warn "Could not enable $unit"
  else
    warn "Unit not found: $unit"
  fi
}

stop_disable_if_exists() {
  local unit="$1"

  if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
    log "Disabling conflicting unit: $unit"
    run systemctl disable --now "$unit" || true
  fi
}

mask_if_exists() {
  local unit="$1"

  if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
    log "Masking $unit"
    run systemctl mask "$unit" || true
  fi
}

prepare_pipewire_jack() {
  # jack2 conflicts with pipewire-jack.
  # PipeWire desktop/laptop setup should use pipewire-jack.
  if installed_has jack2 && ! installed_has pipewire-jack; then
    log "Replacing jack2 with pipewire-jack to avoid package conflict"

    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[dry-run] pacman -Rdd --noconfirm jack2"
    else
      pacman -Rdd --noconfirm jack2
    fi
  fi
}

cleanup_conflicting_nvidia_packages() {
  [[ "$SKIP_NVIDIA" -eq 1 ]] && return 0
  has_nvidia || return 0

  # Use DKMS path. Do not mix with kernel-specific NVIDIA packages.
  local -a conflicts=(
    nvidia
    nvidia-lts
    nvidia-open
    nvidia-open-lts
  )

  local -a installed_conflicts=()

  for pkg in "${conflicts[@]}"; do
    if installed_has "$pkg"; then
      installed_conflicts+=("$pkg")
    fi
  done

  if [[ "${#installed_conflicts[@]}" -gt 0 ]]; then
    log "Removing NVIDIA packages that conflict with DKMS: ${installed_conflicts[*]}"
    run pacman -Rns --noconfirm "${installed_conflicts[@]}" || warn "Could not remove all conflicting NVIDIA packages"
  fi
}

install_helper_scripts() {
  log "Creating helper scripts in /usr/local/bin"

  run install -Dm755 /dev/stdin /usr/local/bin/work-battery <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

sudo tlp bat 2>/dev/null || true
brightnessctl set 35% 2>/dev/null || true

echo "Battery work mode:"
echo "- TLP battery profile"
echo "- brightness 35%"
echo "- iGPU/default apps"
echo "- avoid prime-run unless needed"
EOF

  run install -Dm755 /dev/stdin /usr/local/bin/work-ac <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

sudo tlp ac 2>/dev/null || true
brightnessctl set 70% 2>/dev/null || true

echo "AC work mode:"
echo "- TLP AC profile"
echo "- brightness 70%"
echo "- iGPU/default apps"
echo "- prime-run only for GPU-heavy apps"
EOF

  run install -Dm755 /dev/stdin /usr/local/bin/prime-check <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "== GPU devices =="
lspci | grep -Ei 'vga|3d|display' || true

echo
echo "== NVIDIA =="
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi || true
else
  echo "nvidia-smi not found."
fi

echo
echo "== PRIME =="
if command -v prime-run >/dev/null 2>&1; then
  echo "prime-run found: $(command -v prime-run)"
  echo "Use GPU-heavy app only like:"
  echo "  prime-run app-name"
else
  echo "prime-run not found. Install nvidia-prime."
fi
EOF

  run install -Dm755 /dev/stdin /usr/local/bin/laptop-health <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "== Kernel =="
uname -r

echo
echo "== OS =="
cat /etc/os-release | sed -n '1,8p'

echo
echo "== GPUs =="
lspci | grep -Ei 'vga|3d|display' || true

echo
echo "== Kernel packages =="
pacman -Q | grep -E '^linux|^nvidia' || true

echo
echo "== DKMS =="
if command -v dkms >/dev/null 2>&1; then
  dkms status || true
else
  echo "dkms not found."
fi

echo
echo "== CPU governor/policy =="
grep -H . /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || true
grep -H . /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || true

echo
echo "== TLP =="
if command -v tlp-stat >/dev/null 2>&1; then
  sudo tlp-stat -s -p -b | sed -n '1,180p'
else
  echo "tlp-stat not found."
fi

echo
echo "== zram/swap =="
swapon --show || true
zramctl || true

echo
echo "== Temperatures =="
sensors 2>/dev/null || true

echo
echo "== NVIDIA =="
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi || true
else
  echo "nvidia-smi not found."
fi
EOF
}

configure_tlp() {
  log "Configuring TLP"

  backup_file /etc/tlp.conf

  run install -Dm644 /dev/stdin /etc/tlp.conf <<'EOF'
# /etc/tlp.conf
# Workstation performance + idle efficiency.
# Boosts when needed, saves power when idle.

TLP_ENABLE=1

CPU_SCALING_GOVERNOR_ON_AC=schedutil
CPU_SCALING_GOVERNOR_ON_BAT=schedutil

CPU_ENERGY_PERF_POLICY_ON_AC=balance_performance
CPU_ENERGY_PERF_POLICY_ON_BAT=balance_power

PLATFORM_PROFILE_ON_AC=balanced
PLATFORM_PROFILE_ON_BAT=low-power

RUNTIME_PM_ON_AC=auto
RUNTIME_PM_ON_BAT=auto

PCIE_ASPM_ON_AC=default
PCIE_ASPM_ON_BAT=powersupersave

WIFI_PWR_ON_AC=off
WIFI_PWR_ON_BAT=on

USB_AUTOSUSPEND=1

SOUND_POWER_SAVE_ON_AC=0
SOUND_POWER_SAVE_ON_BAT=1

NMI_WATCHDOG=0

DISK_IDLE_SECS_ON_AC=0
DISK_IDLE_SECS_ON_BAT=2
EOF

  run systemctl restart tlp.service || warn "Could not restart TLP"
}

configure_zram() {
  log "Configuring zram"

  backup_file /etc/systemd/zram-generator.conf

  run install -Dm644 /dev/stdin /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
EOF

  run systemctl daemon-reload
  run systemctl restart systemd-zram-setup@zram0.service 2>/dev/null || true
}

configure_nvidia_wayland() {
  [[ "$SKIP_NVIDIA" -eq 1 ]] && return 0
  has_nvidia || return 0

  log "Configuring NVIDIA DRM modeset for Wayland/Hyprland"

  backup_file /etc/modprobe.d/nvidia.conf

  run install -Dm644 /dev/stdin /etc/modprobe.d/nvidia.conf <<'EOF'
options nvidia_drm modeset=1 fbdev=1
EOF
}

rebuild_dkms_and_initramfs() {
  [[ "$SKIP_NVIDIA" -eq 1 ]] && return 0
  has_nvidia || return 0

  if command -v dkms >/dev/null 2>&1; then
    log "Rebuilding DKMS modules"
    run dkms autoinstall || warn "DKMS autoinstall failed. Check: dkms status"
  else
    warn "dkms not found. nvidia-open-dkms should pull it in, but check package install."
  fi

  if command -v mkinitcpio >/dev/null 2>&1; then
    log "Regenerating initramfs"
    run mkinitcpio -P || warn "mkinitcpio had errors. Check missing modules/headers."
  else
    warn "mkinitcpio not found. Regenerate initramfs manually if needed."
  fi
}

run_sensors_detect() {
  log "Running sensors-detect in automatic mode"

  if command -v sensors-detect >/dev/null 2>&1; then
    run sensors-detect --auto || warn "sensors-detect failed; run sudo sensors-detect manually."
  else
    warn "sensors-detect not found."
  fi
}

setup_services() {
  local cpu_vendor="$1"

  log "Service setup"

  enable_service_if_exists NetworkManager.service
  enable_service_if_exists bluetooth.service

  stop_disable_if_exists power-profiles-daemon.service

  enable_service_if_exists tlp.service
  enable_service_if_exists NetworkManager-dispatcher.service

  mask_if_exists systemd-rfkill.service
  mask_if_exists systemd-rfkill.socket

  if [[ "$cpu_vendor" == "intel" ]]; then
    enable_service_if_exists thermald.service
  fi

  enable_service_if_exists fwupd-refresh.timer
}

setup_lenovo_legion_linux() {
  [[ "$WITH_LEGION" -eq 1 ]] || return 0

  log "Optional LenovoLegionLinux setup requested"

  local aur_helper=""

  if command -v paru >/dev/null 2>&1; then
    aur_helper="paru"
  elif command -v yay >/dev/null 2>&1; then
    aur_helper="yay"
  fi

  if [[ -z "$aur_helper" ]]; then
    warn "No AUR helper found. Install yay/paru, then run:"
    warn "  yay -S lenovolegionlinux-dkms-git"
    return 0
  fi

  local target_user="${SUDO_USER:-}"

  if [[ -z "$target_user" || "$target_user" == "root" ]]; then
    warn "Cannot detect non-root sudo user. Skipping AUR install."
    return 0
  fi

  run sudo -u "$target_user" "$aur_helper" -S --needed --noconfirm lenovolegionlinux-dkms-git || warn "LenovoLegionLinux AUR install failed."
}

main() {
  need_root
  need_arch

  log "Arch workstation tuning for laptop idle efficiency + app performance"

  prepare_pipewire_jack
  cleanup_conflicting_nvidia_packages

  local cpu_vendor
  cpu_vendor="$(detect_cpu_vendor)"

  declare -ga pkgs=(
    base-devel
    git
    curl
    wget
    vim
    networkmanager
    bluez
    bluez-utils
    pipewire
    pipewire-pulse
    pipewire-alsa
    pipewire-jack
    wireplumber
    fwupd
    lm_sensors
    powertop
    btop
    brightnessctl
    tlp
    tlp-rdw
    zram-generator
    gamemode
    mangohud
    pciutils
    usbutils
    mesa
    vulkan-radeon
    libva-mesa-driver
  )

  if [[ "$cpu_vendor" == "amd" ]]; then
    append_unique_pkg amd-ucode
  elif [[ "$cpu_vendor" == "intel" ]]; then
    append_unique_pkg intel-ucode
    append_unique_pkg intel-media-driver
    append_unique_pkg thermald
  else
    warn "Unknown CPU vendor. Skipping microcode package."
  fi

  # Optional fallback kernel.
  # If installing linux-lts, always install linux-lts-headers too.
  # Needed for nvidia-open-dkms.
  if [[ "$NO_LTS" -eq 0 ]]; then
    if kernel_pkg_installed linux && ! kernel_pkg_installed linux-lts && repo_has linux-lts; then
      append_unique_pkg linux-lts
      append_unique_pkg linux-lts-headers
    elif kernel_pkg_installed linux-lts && ! kernel_pkg_installed linux-lts-headers && repo_has linux-lts-headers; then
      append_unique_pkg linux-lts-headers
    fi
  fi

  if [[ "$SKIP_NVIDIA" -eq 0 ]] && has_nvidia; then
    log "NVIDIA GPU detected"

    append_unique_pkg nvidia-utils
    append_unique_pkg nvidia-settings
    append_unique_pkg nvidia-prime
    append_unique_pkg nvtop

    # Use DKMS only. Do not install nvidia-open-lts/nvidia-lts.
    # DKMS handles linux + linux-lts as long as matching headers exist.
    if repo_has nvidia-open-dkms || installed_has nvidia-open-dkms; then
      append_unique_pkg nvidia-open-dkms
    elif repo_has nvidia-dkms || installed_has nvidia-dkms; then
      append_unique_pkg nvidia-dkms
    else
      warn "No NVIDIA DKMS package found. Installing userspace NVIDIA tools only."
    fi

    if kernel_pkg_installed linux || [[ " ${pkgs[*]} " == *" linux "* ]]; then
      append_unique_pkg linux-headers
    fi

    if kernel_pkg_installed linux-lts || [[ " ${pkgs[*]} " == *" linux-lts "* ]]; then
      append_unique_pkg linux-lts-headers
    fi
  else
    log "NVIDIA setup skipped or NVIDIA GPU not detected"
  fi

  install_packages "${pkgs[@]}"

  # Helpers early, so commands exist even if later hardware tuning fails.
  install_helper_scripts

  setup_services "$cpu_vendor"
  configure_tlp
  configure_zram
  configure_nvidia_wayland
  rebuild_dkms_and_initramfs
  run_sensors_detect
  setup_lenovo_legion_linux

  log "Done"

  cat <<'EOF'

Next:

  sudo reboot

After reboot:

  laptop-health
  prime-check
  sudo powertop

Modes:

  work-battery
  work-ac

Test suspend:

  systemctl suspend

Heavy GPU app only:

  prime-run app-name

Useful checks:

  pacman -Q | grep -E '^linux|^nvidia'
  dkms status
  ls /usr/lib/modules
  nvidia-smi

EOF
}

main "$@"

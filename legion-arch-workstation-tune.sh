#!/usr/bin/env bash
# legion-arch-workstation-tune-v2.sh
#
# Arch laptop setup for workstation performance + idle efficiency.
# Fixed for:
#   - nvidia-open-dkms systems
#   - jack2 vs pipewire-jack conflict
#
# Run:
#   chmod +x legion-arch-workstation-tune-v2.sh
#   sudo ./legion-arch-workstation-tune-v2.sh
#
# Optional:
#   sudo ./legion-arch-workstation-tune-v2.sh --with-legion
#   sudo ./legion-arch-workstation-tune-v2.sh --skip-nvidia
#   sudo ./legion-arch-workstation-tune-v2.sh --dry-run

set -Eeuo pipefail

WITH_LEGION=0
SKIP_NVIDIA=0
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --with-legion) WITH_LEGION=1 ;;
    --skip-nvidia) SKIP_NVIDIA=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      sed -n '1,80p' "$0"
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

detect_cpu_vendor() {
  if grep -qi 'AuthenticAMD' /proc/cpuinfo; then
    echo "amd"
  elif grep -qi 'GenuineIntel' /proc/cpuinfo; then
    echo "intel"
  else
    echo "unknown"
  fi
}

has_nvidia() {
  lspci 2>/dev/null | grep -iq nvidia
}

prepare_pipewire_jack() {
  # jack2 conflicts with pipewire-jack.
  # For modern PipeWire desktop/laptop setup, pipewire-jack is preferred.
  if installed_has jack2 && ! installed_has pipewire-jack; then
    log "Replacing jack2 with pipewire-jack to avoid package conflict"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[dry-run] pacman -Rdd --noconfirm jack2"
    else
      pacman -Rdd --noconfirm jack2
    fi
  fi
}

main() {
  need_root
  need_arch

  log "Arch workstation tuning for laptop idle efficiency + app performance"

  prepare_pipewire_jack

  local cpu_vendor
  cpu_vendor="$(detect_cpu_vendor)"

  local -a pkgs=(
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
    pkgs+=(amd-ucode)
  elif [[ "$cpu_vendor" == "intel" ]]; then
    pkgs+=(intel-ucode intel-media-driver thermald)
  else
    warn "Unknown CPU vendor. Skipping microcode package."
  fi

  if kernel_pkg_installed linux && ! kernel_pkg_installed linux-lts && repo_has linux-lts; then
    pkgs+=(linux-lts)
  fi

  if [[ "$SKIP_NVIDIA" -eq 0 ]] && has_nvidia; then
    log "NVIDIA GPU detected"
    pkgs+=(nvidia-utils nvidia-settings nvidia-prime nvtop)

    if installed_has nvidia-open-dkms || repo_has nvidia-open-dkms; then
      pkgs+=(nvidia-open-dkms linux-headers)
    elif installed_has nvidia-open || repo_has nvidia-open; then
      pkgs+=(nvidia-open)
    elif installed_has nvidia || repo_has nvidia; then
      pkgs+=(nvidia)
    else
      warn "No NVIDIA kernel module package found. Installing userspace NVIDIA tools only."
    fi
  else
    log "NVIDIA setup skipped or NVIDIA GPU not detected"
  fi

  install_packages "${pkgs[@]}"

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

  if [[ "$SKIP_NVIDIA" -eq 0 ]] && has_nvidia; then
    log "Configuring NVIDIA DRM modeset for Wayland/Hyprland"
    backup_file /etc/modprobe.d/nvidia.conf
    run install -Dm644 /dev/stdin /etc/modprobe.d/nvidia.conf <<'EOF'
options nvidia_drm modeset=1 fbdev=1
EOF

    if command -v mkinitcpio >/dev/null 2>&1; then
      log "Regenerating initramfs"
      run mkinitcpio -P
    else
      warn "mkinitcpio not found. Regenerate initramfs manually if needed."
    fi
  fi

  log "Running sensors-detect in automatic mode"
  if command -v sensors-detect >/dev/null 2>&1; then
    run sensors-detect --auto || warn "sensors-detect failed; run sudo sensors-detect manually."
  fi

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
echo "Use GPU-heavy app only like:"
echo "  prime-run app-name"
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

  if [[ "$WITH_LEGION" -eq 1 ]]; then
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
    else
      local target_user="${SUDO_USER:-}"
      if [[ -z "$target_user" || "$target_user" == "root" ]]; then
        warn "Cannot detect non-root sudo user. Skipping AUR install."
      else
        run sudo -u "$target_user" "$aur_helper" -S --needed --noconfirm lenovolegionlinux-dkms-git || warn "LenovoLegionLinux AUR install failed."
      fi
    fi
  fi

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

EOF
}

main "$@"

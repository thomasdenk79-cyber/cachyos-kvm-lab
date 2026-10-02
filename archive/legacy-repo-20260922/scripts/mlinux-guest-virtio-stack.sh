#!/usr/bin/env bash
set -Eeuo pipefail

# Install and verify the guest-side VirtIO/SPICE/Mesa stack for an Ubuntu or
# Arch-derived mLinux VM. Run this script inside the guest as its normal user.

usage() { printf '%s\n' "Usage: $(basename "$0") --check|--apply|--verify"; }
log() { printf '[mlinux-guest-virtio] %s\n' "$*"; }

package_family=unknown
if command -v apt-get >/dev/null 2>&1; then
  package_family=apt
elif command -v pacman >/dev/null 2>&1; then
  package_family=pacman
elif command -v dnf >/dev/null 2>&1; then
  package_family=dnf
fi

case "$package_family" in
  apt)
    packages=(
      libgl1-mesa-dri mesa-utils mesa-vulkan-drivers
      libva2 vainfo spice-vdagent qemu-guest-agent
      pciutils ethtool iproute2 usbutils xserver-xorg-input-libinput
    )
    ;;
  pacman)
    packages=(
      mesa mesa-utils vulkan-radeon libva libva-utils
      vulkan-swrast spice-vdagent qemu-guest-agent
      pciutils ethtool iproute2 usbutils xf86-input-libinput
    )
    ;;
  dnf)
    packages=(
      mesa-dri-drivers mesa-demos mesa-vulkan-drivers
      libva-utils spice-vdagent qemu-guest-agent
      pciutils ethtool iproute2 usbutils xorg-x11-drv-libinput
    )
    ;;
  *)
    packages=()
    ;;
esac

check_gpu() {
  command -v lspci >/dev/null 2>&1 || return 1
  lspci -nn | grep -Eqi 'Virtio( 1\.0)? GPU|VGA compatible controller.*Virtio'
}

check_packages() {
  case "$package_family" in
    apt) dpkg-query -W -f='${Status}\n' "${packages[@]}" 2>/dev/null | grep -c 'install ok installed' | grep -qx "${#packages[@]}" ;;
    pacman) pacman -Q "${packages[@]}" >/dev/null 2>&1 ;;
    dnf) rpm -q "${packages[@]}" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

check_dri() {
  [[ -e /usr/lib/x86_64-linux-gnu/dri/virtio_gpu_dri.so ]] \
    || [[ -e /usr/lib/dri/virtio_gpu_dri.so ]] \
    || [[ -e /usr/lib64/dri/virtio_gpu_dri.so ]]
}

renderer() {
  command -v glxinfo >/dev/null 2>&1 || return 1
  [[ -n "${DISPLAY:-}" ]] || return 1
  glxinfo -B 2>/dev/null | awk -F': ' '/OpenGL renderer string:/ {print $2; exit}'
}

check_renderer() {
  local value
  value="$(renderer || true)"
  [[ "$value" == *virgl* || "$value" == *virtio* ]] \
    && ! [[ "$value" == *llvmpipe* ]]
}

apply_packages() {
  [[ "$package_family" != unknown ]] || { log 'unsupported package manager'; return 1; }
  sudo -v
  case "$package_family" in
    apt) sudo -n apt-get update; sudo -n env DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}" ;;
    pacman) sudo -n pacman -Syu --needed --noconfirm "${packages[@]}" ;;
    dnf) sudo -n dnf install -y "${packages[@]}" ;;
  esac
  log 'VirtIO/SPICE/Mesa guest packages applied'
}

case "${1:---check}" in
  --help|-h) usage ;;
  --check)
    check_gpu && check_packages && check_dri \
      && log "guest stack installed; renderer=$(renderer || echo unavailable)" \
      || { log 'guest stack incomplete or no VirtIO GPU detected'; exit 1; }
    ;;
  --apply) check_gpu || { log 'VirtIO GPU is not visible in the guest'; exit 1; }; apply_packages ;;
  --verify)
    check_gpu && check_packages && check_dri && check_renderer \
      && log "VERIFY_PASS renderer=$(renderer)" \
      || { log "VERIFY_FAIL renderer=$(renderer || echo unavailable); llvmpipe means software rendering"; exit 1; }
    ;;
  *) usage >&2; exit 2 ;;
esac

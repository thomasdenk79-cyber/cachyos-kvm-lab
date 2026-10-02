#!/usr/bin/env bash
# Prepare an isolated, reversible Intel iGPU SR-IOV experiment.
# This does not change the default boot entry and never reboots automatically.
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
STATE_DIR=${IGPU_SRIOV_STATE_DIR:-$ROOT_DIR/.vm-lab/intel-igpu-sriov}
SRC_DIR=$STATE_DIR/i915-sriov-dkms
VERSION=${IGPU_SRIOV_VERSION:-2026.09.16}
TAG=${IGPU_SRIOV_TAG:-2026.09.16}
BOOT_ID=intel-sriov-experimental
BOOT_ENTRY=/boot/loader/entries/${BOOT_ID}.conf
TMPFILES=/etc/tmpfiles.d/i915-sriov-numvfs.conf
VFS=${IGPU_SRIOV_VFS:-3}

log(){ printf '[igpu-sriov] %s\n' "$*"; }
die(){ printf '[igpu-sriov] ERROR: %s\n' "$*" >&2; exit 1; }
run_root(){ ((EUID==0)) && "$@" || sudo "$@"; }
need(){ command -v "$1" >/dev/null || die "Fehlt: $1"; }

check_host(){
  need git; need makepkg; need dkms; need mkinitcpio; need bootctl
  local cpu gpu
  cpu=$(lscpu | awk -F: '/Model name/{sub(/^[ \t]+/,"",$2); print $2; exit}')
  gpu=$(lspci -nn | awk '/VGA compatible controller|3D controller/{print; exit}')
  log "CPU: ${cpu:-unbekannt}"
  log "GPU: ${gpu:-unbekannt}"
  [[ "$cpu" == *"11th Gen Intel"* && "$cpu" == *"i5-1145G7"* ]] || log "Warnung: Experiment ist für Tiger-Lake-Iris-Xe gedacht; CPU nicht exakt i5-1145G7."
  [[ -e /sys/devices/pci0000:00/0000:00:02.0 ]] || die "Intel-GPU 0000:00:02.0 nicht gefunden"
  run_root test -d /boot/loader/entries || die "/boot/loader/entries nicht gefunden"
  pacman -Q linux-cachyos-headers dkms >/dev/null || die "linux-cachyos-headers und dkms müssen installiert sein"
  [[ $(bootctl is-secure-boot-enabled 2>/dev/null || echo no) != yes ]] || die "Secure Boot ist aktiv; unsignierte DKMS-Module würden nicht laden"
}

backup_boot(){
  local backup="$STATE_DIR/backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup"
  run_root cp -a /boot/loader/entries "$backup/"
  [[ -e /etc/kernel/cmdline ]] && run_root cp -a /etc/kernel/cmdline "$backup/" || true
  log "Bootzustand gesichert: $backup"
}

fetch_source(){
  mkdir -p "$STATE_DIR"
  if [[ ! -d "$SRC_DIR/.git" ]]; then
    log "Hole i915-sriov-dkms Tag $TAG"
    git clone --branch "$TAG" --depth 1 https://github.com/strongtz/i915-sriov-dkms.git "$SRC_DIR"
  else
    log "Quellstand vorhanden: $SRC_DIR"
  fi
  git -C "$SRC_DIR" describe --always --tags
}

install_driver(){
  log "Baue und installiere DKMS-Paket; das aktive Standardmodul wird noch nicht entladen"
  (cd "$SRC_DIR" && makepkg --syncdeps --noconfirm --needed)
  local pkg
  pkg=$(find "$SRC_DIR" -maxdepth 1 -type f -name "i915-sriov-dkms-${VERSION}-*.pkg.tar.*" | sort | tail -1)
  [[ -s "$pkg" ]] || die "Gebautes DKMS-Paket nicht gefunden"
  run_root pacman -U --noconfirm "$pkg"
  run_root mkinitcpio -P
  run_root dkms status | grep -F "i915-sriov-dkms/${VERSION}" || die "DKMS-Modul wurde nicht registriert"
}

write_boot_entry(){
  local entry
  entry=$(mktemp)
  cat > "$entry" <<'EOF'
title   CachyOS (Intel iGPU SR-IOV experiment)
linux   /vmlinuz-linux-cachyos
initrd  /initramfs-linux-cachyos.img
options zfs=zpcachyos/ROOT/cos/root rw intel_iommu=on iommu=pt i915.enable_guc=3 i915.max_vfs=3 i915.xelp_enable_ccs=1 module_blacklist=xe
EOF
  run_root install -m 0644 "$entry" "$BOOT_ENTRY"
  rm -f "$entry"
  log "Separater Boot-Eintrag installiert: $BOOT_ENTRY"
  log "Standard-Eintrag bleibt unverändert; Reboot wird nicht automatisch ausgeführt."
}

enable_vfs(){
  printf 'w /sys/devices/pci0000:00/0000:00:02.0/sriov_numvfs - - - - %s\n' "$VFS" | run_root tee "$TMPFILES" >/dev/null
  log "Automatische VF-Erzeugung vorbereitet: $VFS VFs ($TMPFILES)"
  log "Für den ersten Test ist ein manueller echo-Test nach dem SR-IOV-Boot sicherer."
}

create_vfs(){
  local path=/sys/devices/pci0000:00/0000:00:02.0/sriov_numvfs
  [[ -w "$path" ]] || die "SR-IOV-Schnittstelle fehlt; zuerst über den experimentellen Boot-Eintrag starten"
  printf '%s\n' "$VFS" | run_root tee "$path" >/dev/null
  log "$VFS VFs angefordert"
  run_root lspci -Dnn | awk '/00:02\.[1-9]/{print}' || true
}

remove(){
  run_root rm -f "$BOOT_ENTRY" "$TMPFILES"
  run_root pacman -Rns --noconfirm i915-sriov-dkms || true
  run_root mkinitcpio -P
  log "Experiment entfernt; Standard-i915 bleibt aktiv."
}

status(){
  printf 'Boot entry: '; run_root test -f "$BOOT_ENTRY" && echo present || echo absent
  printf 'DKMS: '; run_root dkms status | grep -F 'i915-sriov-dkms' || true
  printf 'VFs: '; cat /sys/devices/pci0000:00/0000:00:02.0/{sriov_totalvfs,sriov_numvfs} 2>/dev/null | paste -sd / || echo unavailable
  lspci -Dnn | awk '/VGA compatible controller|3D controller/{print}'
}

case "${1:-prepare}" in
  check) check_host;;
  prepare) check_host; backup_boot; fetch_source; install_driver; write_boot_entry;;
  enable-vfs) check_host; enable_vfs;;
  create-vfs) check_host; create_vfs;;
  status) status;;
  remove) remove;;
  *) echo "Usage: $0 {check|prepare|enable-vfs|create-vfs|status|remove}"; exit 2;;
esac

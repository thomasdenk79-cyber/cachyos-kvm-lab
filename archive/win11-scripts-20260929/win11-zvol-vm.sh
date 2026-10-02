#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# High-performance Windows 11 on ZFS. All tuning knobs are collected here.
# Change values here (or export the matching WIN11_* variable) before --apply.
#
# Identity: keep these stable after Intune enrollment. Changing UUID/serial/MAC
# makes Windows see a different device.
VM_NAME="${VM_NAME:-win11-siemens}"
DOMAIN_UUID="${WIN11_DOMAIN_UUID:-e39af3f0-0d5f-4932-8934-9fe33d19ce86}"
SMBIOS_SERIAL="${WIN11_SMBIOS_SERIAL:-WIN11-E39AF3F00D5F493289349FE33D19CE86}"
DISK_SERIAL="${WIN11_DISK_SERIAL:-${SMBIOS_SERIAL}-DISK}"
# QEMU limits SCSI disk serials to 36 characters.
DISK_SERIAL="${DISK_SERIAL:0:36}"
MAC="${WIN11_MAC:-52:54:00:df:a5:d1}"
NETWORK_MODEL="${WIN11_NETWORK_MODEL:-e1000e}" # stock OOBE driver; switch to virtio after NetKVM install
NETWORK_LINK_STATE="${WIN11_NETWORK_LINK_STATE:-}" # optional: down during offline OOBE
NETWORK_LINK_STATE="${WIN11_LINK:-$NETWORK_LINK_STATE}"
PCI_HOSTDEV_BDF="${WIN11_PCI_HOSTDEV_BDF:-}" # e.g. 0000:00:1f.6
PCI_HOSTDEV_IFACE="${WIN11_PCI_HOSTDEV_IFACE:-}" # e.g. enp0s31f6
PCI_HOSTDEV_CONNECTION="${WIN11_PCI_HOSTDEV_CONNECTION:-}"
PCI_HOSTDEV_AUTO="${WIN11_PCI_HOSTDEV_AUTO:-0}"
PCI_HOSTDEV_MAC="${WIN11_PCI_HOSTDEV_MAC:-$MAC}"
PCI_HOSTDEV_FALLBACK_IFACE="${WIN11_PCI_HOSTDEV_FALLBACK_IFACE:-}"
PCI_WATCHER_ENABLED="${WIN11_PCI_WATCHER:-1}" # restore host NIC automatically on VM stop
# A first VM profile can set this guard to make accidental PCI passthrough
# impossible even when stale shell environment variables are present.
DISABLE_PCI_PASSTHROUGH="${WIN11_DISABLE_PCI_PASSTHROUGH:-0}"

# ZFS/ZVOL: fixed provisioning is the default for predictable latency and to
# avoid pool ENOSPC during a VM write burst. Set ZVOL_SPARSE=1 to test a thin
# (dynamic) ZVOL; thin provisioning saves space but needs free-space monitoring.
POOL="${WIN11_ZFS_POOL:-zpcachyos}"
ZVOL="${WIN11_ZVOL:-${POOL}/vms/win11}"
DISK_BACKEND="${WIN11_DISK_BACKEND:-zvol}" # zvol or qcow2
DISK_PATH="${WIN11_DISK_PATH:-}"
VOLSIZE="${WIN11_VOLSIZE:-200G}"
ZVOL_SPARSE="${WIN11_ZVOL_SPARSE:-0}"       # 0=fixed, 1=dynamic/thin
ZVOL_VOLBLOCKSIZE="${WIN11_VOLBLOCKSIZE:-64K}" # good NTFS/KVM compromise
ZFS_COMPRESSION="${WIN11_COMPRESSION:-zstd-1}" # light host compression for VM blocks
ZFS_SYNC="${WIN11_SYNC:-standard}"          # durability; disabled is benchmark-only
ZFS_PRIMARYCACHE="${WIN11_PRIMARYCACHE:-metadata}" # avoid double-caching guest filesystem data
ZFS_ATIME="${WIN11_ATIME:-off}"
if [[ "$DISK_BACKEND" == zvol ]]; then
  DISK_PATH="${DISK_PATH:-/dev/zvol/${ZVOL}}"
else
  DISK_PATH="${DISK_PATH:-/var/lib/libvirt/images/${VM_NAME}.qcow2}"
fi

# Guest CPU/RAM: host-passthrough and 1x6x1 match the host's six physical cores;
# leave SMT threads for the host, ZFS and libvirt during installation tests.
RAM_MIB="${WIN11_RAM_MIB:-16384}"
VCPUS="${WIN11_VCPUS:-6}"
CPU_MODE="${WIN11_CPU_MODE:-host-passthrough}"
CPU_SOCKETS="${WIN11_CPU_SOCKETS:-1}"
CPU_CORES="${WIN11_CPU_CORES:-6}"
CPU_THREADS="${WIN11_CPU_THREADS:-1}"
HUGEPAGES="${WIN11_HUGEPAGES:-0}"           # Phase 1 is conservative; opt in after stability testing
# WIN11_HUGEPAGES=0 explicitly selects ordinary anonymous guest RAM.  This is
# useful on hosts where hugepage preallocation cannot obtain a contiguous block.
USE_HUGEPAGES=1
(( HUGEPAGES > 0 )) || USE_HUGEPAGES=0

# Disk I/O: io_uring is the preferred modern Linux path; cache=none avoids
# double caching. VirtIO-SCSI, queues and discard can be varied for benchmarks.
DISK_BUS="${WIN11_DISK_BUS:-sata}" # SATA is visible in stock WinPE; set scsi after driver validation
SCSI_MODEL="${WIN11_SCSI_MODEL:-virtio-scsi}"
IO_MODE="${WIN11_IO_MODE:-io_uring}"         # alternative to test: native
CACHE_MODE="${WIN11_CACHE_MODE:-none}"
DISCARD_MODE="${WIN11_DISCARD_MODE:-unmap}"
DETECT_ZEROES="${WIN11_DETECT_ZEROES:-unmap}"
SCSI_IOTHREAD="${WIN11_SCSI_IOTHREAD:-1}"

# Firmware/security/display: UEFI + TPM are required for a normal Win11 setup.
UEFI_BOOT="${WIN11_UEFI_BOOT:-yes}"
SECURE_BOOT="${WIN11_SECURE_BOOT:-1}"
TPM_MODEL="${WIN11_TPM_MODEL:-tpm-crb}"
OS_VARIANT="${WIN11_OS_VARIANT:-win11}"
GRAPHICS_TYPE="${WIN11_GRAPHICS_TYPE:-spice}"
VIDEO_MODEL="${WIN11_VIDEO_MODEL:-vga}"       # vga is the safe Win11 installer fallback; virtio after guest driver validation
SPICE_STREAMING_MODE="${WIN11_SPICE_STREAMING:-off}" # off reduces CPU/latency on LAN
SPICE_IMAGE_COMPRESSION="${WIN11_SPICE_COMPRESSION:-off}" # test auto for slow links

# Remote access: these are host-side clients. Windows RDP itself must be
# enabled and authorized inside the guest; no guest policy is changed here.
RDP_CLIENT="${WIN11_RDP_CLIENT:-xfreerdp3}"
RDP_FLAGS="${WIN11_RDP_FLAGS:-/network:auto /dynamic-resolution /gfx:avc444}"

# Media: defaults to a user-visible ISO directory. Windows URL must be supplied
# from an authorized Microsoft download; VirtIO has a stable Fedora mirror URL.
ISO_DIR="${WIN11_ISO_DIR:-${HOME}/isos/win11}"
VENTOY_ISO_DIR="${WIN11_VENTOY_ISO_DIR:-/run/media/${USER}/Ventoy/ISO/Imported}"
WIN11_ISO_PATH="${WIN11_ISO_PATH:-}"
WIN11_ISO_URL="${WIN11_ISO_URL:-}"
VIRTIO_ISO_PATH="${VIRTIO_ISO_PATH:-}"
VIRTIO_ISO_URL="${VIRTIO_ISO_URL:-https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso}"
MEDIA_MODE="${WIN11_MEDIA_MODE:-download-if-missing}"
MEDIA_CACHE_DIR="${WIN11_MEDIA_CACHE_DIR:-/var/lib/libvirt/boot}"
START_VM="${WIN11_START_VM:-1}"
REFRESH_MEDIA="${WIN11_REFRESH_MEDIA:-0}"
BOOT_FROM_ISO="${WIN11_BOOT_FROM_ISO:-0}"
ENROLL_SECURE_BOOT_KEYS="${WIN11_ENROLL_SECURE_BOOT_KEYS:-1}"
# Optional local Windows account for unattended setup. Keep these values out of
# Git; pass them via the environment or an external 0600 credentials file.
WIN11_VM_USER="${WIN11_VM_USER:-}"
WIN11_VM_PASSWORD="${WIN11_VM_PASSWORD:-}"
WIN11_CREDENTIAL_FILE="${WIN11_CREDENTIAL_FILE:-$HOME/win11_cred.txt}"
if [[ -f "$WIN11_CREDENTIAL_FILE" ]]; then
  # Local-only file; never commit it. Read values without shell evaluation so
  # passwords may contain quotes, backslashes, spaces, or shell metacharacters.
  credential_value() { sed -n "s/^$1=//p" "$WIN11_CREDENTIAL_FILE" | head -n1; }
  WIN11_VM_USER="${WIN11_VM_USER:-$(credential_value vm_user)}"
  WIN11_VM_PASSWORD="${WIN11_VM_PASSWORD:-$(credential_value vm_password)}"
fi
if [[ "$WIN11_VM_USER" == *@* ]]; then
  log() { printf '[win11-vm] %s\n' "$*"; }
  log 'Credential looks like a Microsoft account; leaving local account/OOBE manual for MFA.'
  WIN11_VM_USER=""
  WIN11_VM_PASSWORD=""
fi
# Manual OOBE is the safe default. Automatic servicing during OOBE previously
# left a pending CloudExperienceHost update and caused the boot-repair loop.
AUTOATTEND="${WIN11_AUTOATTEND:-0}"
WIN11_IMAGE_INDEX="${WIN11_IMAGE_INDEX:-6}" # Windows 11 Pro in the standard multi-edition ISO
REMASTERED_ISO="${WIN11_REMASTERED_ISO:-$MEDIA_CACHE_DIR/${VM_NAME}-install.iso}"
SUPPORT_ISO="${WIN11_SUPPORT_ISO:-$MEDIA_CACHE_DIR/${VM_NAME}-support.iso}"
ORIGINAL_ISO="${WIN11_ORIGINAL_ISO:-${WIN11_ISO_PATH:-}}"
PATCHED_WIM="${WIN11_PATCHED_WIM:-}"
ISO_BUILD_OUTPUT="${WIN11_ISO_BUILD_OUTPUT:-$MEDIA_CACHE_DIR/${VM_NAME}-patched.iso}"
ENROLLED_VARS_TEMPLATE="${WIN11_ENROLLED_VARS_TEMPLATE:-/var/lib/libvirt/qemu/nvram/OVMF_VARS.4m.ms-enrolled.fd}"
SNAPSHOT_DIR="${WIN11_SNAPSHOT_DIR:-$MEDIA_CACHE_DIR/${VM_NAME}-snapshots}"
SNAPSHOT_NAME="${WIN11_SNAPSHOT_NAME:-}"
SNAPSHOT_BEFORE_START="${WIN11_SNAPSHOT_BEFORE_START:-1}"
REQUIRE_PATCHED_ISO="${WIN11_REQUIRE_PATCHED_ISO:-0}"
VM_QEMU_USER="${WIN11_QEMU_USER:-libvirt-qemu}" # used for optional ACLs
VM_ADMIN_USER="${WIN11_ADMIN_USER:-${SUDO_USER:-$USER}}"
VM_ADMIN_GROUPS=(libvirt kvm)                    # lets virsh/virt-manager run without sudo
ADD_ADMIN_GROUPS="${WIN11_ADD_GROUPS:-1}"

mount_external_ventoy() {
  local device mountpoint current_mount
  command -v lsblk >/dev/null 2>&1 || return 0
  device="$(lsblk -nrpo PATH,LABEL,FSTYPE,TYPE | awk '$2 == "Ventoy" && $3 == "exfat" && $4 == "part" {print $1; exit}')"
  [[ -n "$device" ]] || return 0
  current_mount="$(findmnt -rn -S "$device" -o TARGET 2>/dev/null | head -n1 || true)"
  if [[ -n "$current_mount" ]]; then
    VENTOY_ISO_DIR="$current_mount/ISO/Imported"
    return 0
  fi
  mountpoint="/run/media/${USER}/Ventoy"
  if [[ ! -d "$mountpoint" ]]; then
    if (( EUID == 0 )); then install -d -m 0755 "$mountpoint"; else sudo install -d -m 0755 "$mountpoint"; fi
  fi
  if (( EUID == 0 )); then
    mount -o uid="$(id -u "$USER")",gid="$(id -g "$USER")",umask=022 "$device" "$mountpoint"
  else
    sudo mount -o uid="$(id -u "$USER")",gid="$(id -g "$USER")",umask=022 "$device" "$mountpoint"
  fi
  VENTOY_ISO_DIR="$mountpoint/ISO/Imported"
  printf '[win11-vm] Mounted Ventoy media: %s -> %s\n' "$device" "$mountpoint"
}

# Packages: kept configurable so CachyOS/Arch variants can replace a component.
# Arch/CachyOS splits the generic "qemu-tools" contents into qemu-img and
# qemu-system-x86; there is no qemu-tools package in the official repos.
REQUIRED_PACKAGES=(qemu-desktop qemu-system-x86 qemu-base qemu-img libvirt virt-install virt-manager virt-viewer edk2-ovmf virt-firmware swtpm spice spice-gtk spice-protocol spice-vdagent dnsmasq iptables acl freerdp remmina)

# Prefer explicitly configured paths, then search mounted Ventoy/data media.
# The external SSD may be mounted under either /run/media/$USER or /media/$USER;
# do not assume one exact mountpoint or one exact ISO filename.
mount_external_ventoy
MEDIA_ROOTS=()
for media_root in "$VENTOY_ISO_DIR" "/run/media/$USER" "/media/$USER" "/mnt"; do
  [[ -d "$media_root" ]] || continue
  [[ " ${MEDIA_ROOTS[*]} " == *" $media_root "* ]] || MEDIA_ROOTS+=("$media_root")
done

find_media_iso() {
  local pattern="$1" root candidate
  for root in "${MEDIA_ROOTS[@]}"; do
    candidate="$(find "$root" -maxdepth 7 -type f -iname '*.iso' -printf '%p\n' 2>/dev/null \
      | awk -v pattern="$pattern" 'BEGIN { IGNORECASE=1 } $0 ~ pattern { print; exit }')"
    if [[ -n "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

if [[ -z "$WIN11_ISO_PATH" ]]; then
  for candidate in \
      "$VENTOY_ISO_DIR/Windows11-25H2-Official-Multi-DE.iso" \
      "$ISO_DIR/Win11_25H2_German_x64.iso"; do
    if [[ -f "$candidate" ]]; then
      WIN11_ISO_PATH="$candidate"
      break
    fi
  done
  [[ -n "$WIN11_ISO_PATH" ]] || WIN11_ISO_PATH="$(find_media_iso '(^|/)(windows[ _-]*11|win[ _-]*11).*[.]iso$' || true)"
fi

if [[ -n "$WIN11_ISO_PATH" && -f "$WIN11_ISO_PATH" ]]; then
  ISO_DIR="$(dirname "$WIN11_ISO_PATH")"
fi

if [[ -z "$VIRTIO_ISO_PATH" ]]; then
  if [[ -f "$ISO_DIR/virtio-win.iso" ]]; then
    VIRTIO_ISO_PATH="$ISO_DIR/virtio-win.iso"
  else
    VIRTIO_ISO_PATH="$(find_media_iso '(^|/)(virtio[-_ ]*win|virtio).*[.]iso$' || true)"
  fi
fi
VIRTIO_ISO_PATH="${VIRTIO_ISO_PATH:-${ISO_DIR}/virtio-win.iso}"

# A previous run may already have staged media in libvirt's boot cache while
# the original removable mount is no longer present. Reuse that copy instead
# of leaving WIN11_ISO_PATH empty and attempting to copy an empty source path.
if [[ -z "$WIN11_ISO_PATH" ]]; then
  staged_windows_iso="$MEDIA_CACHE_DIR/Windows11-25H2-Official-Multi-DE.iso"
  [[ -f "$staged_windows_iso" ]] && WIN11_ISO_PATH="$staged_windows_iso"
fi
if [[ -z "$VIRTIO_ISO_PATH" || ! -f "$VIRTIO_ISO_PATH" ]]; then
  staged_virtio_iso="$MEDIA_CACHE_DIR/virtio-win.iso"
  [[ -f "$staged_virtio_iso" ]] && VIRTIO_ISO_PATH="$staged_virtio_iso"
fi

SYSCTL_FILE="/etc/sysctl.d/99-${VM_NAME}-hugepages.conf"
MODE=check
INSTALL_PACKAGES=1
OPERATION_MODE=existing
FORCE=0

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '[win11-vm] %s\n' "$*"; }
[[ "$DISK_BACKEND" == zvol || "$DISK_BACKEND" == qcow2 ]] || die "Unsupported disk backend: $DISK_BACKEND (use zvol or qcow2)"
usage() { cat <<'EOF'
Usage: scripts/win11-zvol-vm.sh [--prepare|--check|--verify|--install|start|snapshot|rollback|rebuild|--build-iso|--dry-run] [--no-install] [--fresh-install --force]
--prepare     install host packages/groups, mount/find media and stage ISOs
--check       read-only prerequisite check (default)
--install     create the configured disk backend and define/start the VM
--snapshot    save a ZFS pre-autopilot snapshot plus NVRAM and swtpm state
--rollback   restore a named snapshot and its saved NVRAM/swtpm state
snapshot NAME / rollback NAME / rebuild --force  checkpoint workflow aliases
verify        verify the inactive/current VM definition without changing it
start         start the existing VM without rebuilding it
--build-iso  replace sources/install.wim in an original ISO (no VM action)
--dry-run     print planned mutating commands without executing them
--apply       compatibility alias for --install
--no-install  skip package installation in --prepare mode
--fresh-install --force  explicitly destroy and recreate this VM and its disk

Set WIN11_ISO_URL to an authorized Microsoft download URL, or provide WIN11_ISO_PATH.
EOF
}
while (($#)); do
  case "$1" in
    --prepare) MODE=prepare; shift;;
    --check) MODE=check; shift;;
    --verify|verify) MODE=verify; shift;;
    --install|install|--apply) MODE=install; shift;;
    --snapshot|snapshot) MODE=snapshot; shift; [[ $# -gt 0 && "$1" != -* ]] && SNAPSHOT_NAME="$1" && shift;;
    --rollback|rollback) MODE=rollback; shift; [[ $# -gt 0 && "$1" != -* ]] && SNAPSHOT_NAME="$1" && shift;;
    rebuild) MODE=install; OPERATION_MODE=fresh-install; shift;;
    start) MODE=start; shift;;
    --build-iso) MODE=build-iso; shift;;
    --dry-run) MODE=dry; shift;;
    --apply) MODE=apply; shift;;
    --no-install) INSTALL_PACKAGES=0; shift;;
    --fresh-install) OPERATION_MODE=fresh-install; shift;;
    --force) FORCE=1; shift;;
    -h|--help) usage; exit 0;;
    *) die "unknown option: $1";;
  esac
done
[[ "$MODE" == prepare || "$MODE" == install || "$MODE" == start || "$MODE" == verify ]] && DRY_RUN=0 || DRY_RUN=1
if [[ "$OPERATION_MODE" == fresh-install && "$FORCE" != 1 ]]; then
  die '--fresh-install requires --force; existing VM/ZVOL is never removed implicitly.'
fi
run() { if (( DRY_RUN )); then printf '+ '; printf '%q ' "$@"; printf '\n'; else "$@"; fi; }
as_root() { if (( EUID == 0 )); then run "$@"; else run sudo "$@"; fi; }

check_host() {
  local failed=0
  log "VM=$VM_NAME pool=$POOL zvol=$ZVOL size=$VOLSIZE RAM=${RAM_MIB}MiB vCPUs=$VCPUS"
  log "2MiB hugepages: configured=$(cat /proc/sys/vm/nr_hugepages 2>/dev/null || echo unavailable), requested=$HUGEPAGES"
  for c in zfs zpool curl qemu-img virt-fw-vars; do
    command -v "$c" >/dev/null || { log "MISSING command: $c"; failed=1; }
  done
  for c in virsh virt-install virt-manager; do
    command -v "$c" >/dev/null || { log "MISSING command: $c"; failed=1; }
  done
  if [[ ! -e /dev/zfs ]]; then
    if grep -qE '^[[:space:]]*249[[:space:]]+zfs$' /proc/misc 2>/dev/null; then
      log "ZFS kernel module is loaded, but /dev/zfs is not visible in this environment"
    else
      log "ZFS device is unavailable: /dev/zfs"
    fi
    failed=1
  elif command -v zpool >/dev/null && timeout 5s zpool list -H -o name "$POOL" >/dev/null 2>&1; then
    log "ZFS pool available: $POOL"
  else
    log "ZFS pool unavailable: $POOL"
    failed=1
  fi
  [[ -f "$WIN11_ISO_PATH" ]] && log "Windows ISO present: $WIN11_ISO_PATH" || { log "Windows ISO missing: $WIN11_ISO_PATH"; failed=1; }
  [[ -f "$VIRTIO_ISO_PATH" ]] && log "VirtIO ISO present: $VIRTIO_ISO_PATH" || { log "VirtIO ISO missing: $VIRTIO_ISO_PATH"; failed=1; }
  if [[ -f "$SUPPORT_ISO" ]]; then
    validate_autounattend_iso || failed=1
  else
    log "Autounattend ISO absent; it will not be attached. Manual setup required."
  fi
  return "$failed"
}

validate_autounattend_iso() {
  command -v 7z >/dev/null || { log 'Autounattend check failed: 7z missing'; return 1; }
  local dir xml efi index account firstlogon
  dir="$(mktemp -d)"
  7z e -y -o"$dir" "$SUPPORT_ISO" autounattend.xml >/dev/null 2>&1 || {
    log "Autounattend check failed: no autounattend.xml in $SUPPORT_ISO"; return 1;
  }
  xml="$dir/autounattend.xml"
  efi="$(sed -n 's/.*<CreatePartition[^>]*>.*<Order>1<\/Order><Type>EFI<\/Type><Size>\([^<]*\)<\/Size>.*/\1/p' "$xml" | head -1)"
  index="$(sed -n 's#.*<Key>/IMAGE/INDEX</Key><Value>\([^<]*\)</Value>.*#\1#p' "$xml" | head -1)"
  account="$(grep -q '<LocalAccount' "$xml" && echo yes || echo no)"
  firstlogon="$(grep -q '<FirstLogonCommands' "$xml" && echo yes || echo no)"
  log "Autounattend check: EFI=${efi:-unknown}MiB, ImageIndex=${index:-unknown}, local account=$account, FirstLogonCommands=$firstlogon"
  [[ "$efi" == 512 && "$index" == 6 ]] || { log 'Autounattend rejected: EFI must be 512 MiB and ImageIndex must be 6'; return 1; }
  if grep -Eiq 'windows update|winget|usoclient|wuauclt|install.*update' "$xml"; then
    log 'Autounattend rejected: update/winget step detected during OOBE'; return 1
  fi
  log 'Autounattend accepted; attaching it as a data CD.'
}

install_packages() {
  (( INSTALL_PACKAGES )) || return 0
  command -v pacman >/dev/null || die 'pacman is required on CachyOS/Arch Linux.'
  local missing=() p
  for p in "${REQUIRED_PACKAGES[@]}"; do pacman -Q "$p" >/dev/null 2>&1 || missing+=("$p"); done
  ((${#missing[@]} == 0)) || as_root pacman -S --needed --noconfirm "${missing[@]}"
}

enable_libvirt() {
  if systemctl list-unit-files libvirtd.service >/dev/null 2>&1; then
    as_root systemctl enable --now libvirtd.service
  elif systemctl list-unit-files virtqemud.socket >/dev/null 2>&1; then
    as_root systemctl enable --now virtqemud.socket virtnetworkd.socket
  fi
  if [[ "$ADD_ADMIN_GROUPS" == 1 ]]; then
    as_root usermod -aG "$(IFS=,; printf '%s' "${VM_ADMIN_GROUPS[*]}")" "$VM_ADMIN_USER"
    log "User $VM_ADMIN_USER was added to ${VM_ADMIN_GROUPS[*]}; a new login session is required."
  fi
}

ensure_default_network() {
  local net_state
  if ! as_root virsh -c qemu:///system net-info default >/dev/null 2>&1; then
    die "libvirt default network is missing; install the distribution default network definition"
  fi
  net_state="$(as_root virsh -c qemu:///system net-info default 2>/dev/null | awk -F: '/^Active:/ {gsub(/[[:space:]]/, "", $2); print $2}')"
  [[ "$net_state" == yes ]] || as_root virsh -c qemu:///system net-start default
  as_root virsh -c qemu:///system net-autostart default >/dev/null
}

ensure_vm_firewall() {
  command -v ufw >/dev/null 2>&1 || { log 'ufw not installed; leaving host firewall unchanged'; return 0; }
  [[ "$(sudo ufw status 2>/dev/null | head -1)" == 'Status: active' ]] || { log 'ufw inactive; leaving firewall unchanged'; return 0; }
  local uplink
  uplink="$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"
  [[ -n "$uplink" ]] || die 'Could not determine uplink interface for libvirt NAT.'
  as_root ufw allow in on virbr0 to any port 67 proto udp >/dev/null
  as_root ufw allow in on virbr0 to any port 53 proto udp >/dev/null
  as_root ufw allow in on virbr0 to any port 53 proto tcp >/dev/null
  as_root ufw allow in on virbr0 to any port 3389 proto tcp >/dev/null
  as_root ufw route allow in on virbr0 out on "$uplink" >/dev/null
  as_root sysctl -w net.ipv4.ip_forward=1 >/dev/null
  log "UFW/libvirt NAT enabled: virbr0 -> $uplink; no inbound LAN-to-guest rule added"
}

reserve_hugepages() {
  as_root install -d -m 0755 /etc/sysctl.d
  if [[ "$MEDIA_MODE" == disabled ]]; then
    die 'Media download disabled and an ISO is missing.'
  fi
  if (( DRY_RUN )); then
    printf '+ write %q: vm.nr_hugepages = %s\n' "$SYSCTL_FILE" "$HUGEPAGES"
  elif (( EUID == 0 )); then
    printf 'vm.nr_hugepages = %s\n' "$HUGEPAGES" > "$SYSCTL_FILE"
  else
    printf 'vm.nr_hugepages = %s\n' "$HUGEPAGES" | sudo tee "$SYSCTL_FILE" >/dev/null
  fi
  as_root sysctl -w "vm.nr_hugepages=$HUGEPAGES"
  local actual
  actual="$(cat /proc/sys/vm/nr_hugepages 2>/dev/null || echo 0)"
  if (( actual < HUGEPAGES )); then
    log "Only $actual/$HUGEPAGES hugepages available; releasing partial reservation and using normal guest RAM"
    as_root sysctl -w vm.nr_hugepages=0
    USE_HUGEPAGES=0
  fi
}

download_media() {
  if (( DRY_RUN )); then
    log "Would download VirtIO ISO from $VIRTIO_ISO_URL"
    if [[ -e "$WIN11_ISO_PATH" ]]; then
      log "Windows ISO already present: $WIN11_ISO_PATH"
    elif [[ -n "$WIN11_ISO_URL" ]]; then
      log "Would download Windows ISO from WIN11_ISO_URL"
    else
      log "Windows ISO URL still required for apply"
    fi
    return 0
  fi
  as_root install -d -m 0755 "$(dirname "$WIN11_ISO_PATH")" "$(dirname "$VIRTIO_ISO_PATH")"
  [[ -e "$VIRTIO_ISO_PATH" ]] || as_root curl -fL --retry 3 "$VIRTIO_ISO_URL" -o "$VIRTIO_ISO_PATH"
  if [[ ! -e "$WIN11_ISO_PATH" ]]; then
    [[ -n "$WIN11_ISO_URL" ]] || die "Set WIN11_ISO_URL or provide $WIN11_ISO_PATH."
    as_root curl -fL --retry 3 "$WIN11_ISO_URL" -o "$WIN11_ISO_PATH"
  fi
  set_media_permissions
}

set_media_permissions() {
  as_root chmod 0644 "$WIN11_ISO_PATH" "$VIRTIO_ISO_PATH"
  if command -v setfacl >/dev/null 2>&1 && getent passwd "$VM_QEMU_USER" >/dev/null 2>&1; then
    # Permit only the libvirt QEMU account to traverse/read a custom home ISO path.
    as_root setfacl -m "u:${VM_QEMU_USER}:rx" "$ISO_DIR" || log "ACL unsupported on $ISO_DIR; using existing mount permissions"
    as_root setfacl -m "u:${VM_QEMU_USER}:--x" "$(dirname "$ISO_DIR")" || true
  else
    log "No ACL applied; ensure $VM_QEMU_USER can traverse/read $ISO_DIR"
  fi
}

stage_media() {
  local source target
  for source in "$WIN11_ISO_PATH" "$VIRTIO_ISO_PATH"; do
    # Always detach removable media from the VM definition.  libvirt/QEMU may
    # still be denied by mount policy even when the qemu user can read the ISO.
    if [[ "$source" != /run/media/* && "$source" != /media/* && "$source" != /mnt/* ]] \
      && sudo -u "$VM_QEMU_USER" test -r "$source" 2>/dev/null; then
      continue
    fi
    target="$MEDIA_CACHE_DIR/$(basename "$source")"
    if [[ -f "$target" && "$REFRESH_MEDIA" != 1 ]]; then
      log "Using existing staged media: $target"
      if [[ "$source" == "$WIN11_ISO_PATH" ]]; then WIN11_ISO_PATH="$target"; else VIRTIO_ISO_PATH="$target"; fi
      continue
    fi
    log "Staging inaccessible media for $VM_QEMU_USER: $source -> $target"
    as_root install -d -m 0755 "$MEDIA_CACHE_DIR"
    if [[ "$source" != "$target" ]]; then
      as_root cp --reflink=auto --sparse=always -- "$source" "$target"
    fi
    as_root chmod 0644 "$target"
    if [[ "$source" == "$WIN11_ISO_PATH" ]]; then
      WIN11_ISO_PATH="$target"
    else
      VIRTIO_ISO_PATH="$target"
    fi
  done
  ISO_DIR="$MEDIA_CACHE_DIR"
}

build_install_iso() {
  (( AUTOATTEND )) || return 0
  command -v xorriso >/dev/null || die 'xorriso is required to build the unattended ISO.'
  command -v 7z >/dev/null || die '7z is required to extract VirtIO drivers.'
  if [[ -f "$SUPPORT_ISO" && "$REFRESH_MEDIA" != 1 ]]; then
    log "Using existing unattended support ISO: $SUPPORT_ISO"
    return 0
  fi
  local work answer tmp_iso
  work="$(mktemp -d)"
  answer="$work/Autounattend.xml"
  tmp_iso="$SUPPORT_ISO.tmp.$$"
  trap 'rm -rf "$work" "$tmp_iso"' RETURN
  mkdir -p "$work/Drivers" "$work/guest-agent"
  7z x -y -o"$work/Drivers" "$VIRTIO_ISO_PATH" \
    'vioscsi/w11/amd64/*' 'viostor/w11/amd64/*' 'NetKVM/w11/amd64/*' >/dev/null
  7z e -y -o"$work/guest-agent" "$VIRTIO_ISO_PATH" \
    'guest-agent/qemu-ga-x86_64.msi' \
    >/dev/null
  cat > "$work/Win11-PostInstall.ps1" <<'PS1'
$ErrorActionPreference = 'Continue'
Get-NetFirewallRule | Where-Object { $_.DisplayGroup -match 'Remote|Remotedesktop' } | Enable-NetFirewallRule
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
Set-Service -Name TermService -StartupType Automatic
Start-Service -Name TermService
# Do not install Windows updates while OOBE/CloudExperienceHost is active.
# Servicing the OOBE binaries here can leave a pending reboot with an
# unusable EFI/BCD state. Run updates only after OOBE and Intune enrollment.
$ga = Join-Path $PSScriptRoot 'guest-agent\qemu-ga-x86_64.msi'
if (Test-Path $ga) { Start-Process msiexec.exe -ArgumentList "/i `"$ga`" /qn /norestart" -Wait }
# Optional winget installs are intentionally deferred until after OOBE/Intune.

New-Item -ItemType File -Force "$env:ProgramData\Siemens-Win11-PostInstall.done" | Out-Null
PS1
WIN11_VM_USER="$WIN11_VM_USER" WIN11_VM_PASSWORD="$WIN11_VM_PASSWORD" WIN11_IMAGE_INDEX="$WIN11_IMAGE_INDEX" python3 - "$answer" <<'PY'
import html, os, sys
out = sys.argv[1]
user = os.environ.get("WIN11_VM_USER", "")
password = os.environ.get("WIN11_VM_PASSWORD", "")
image_index = os.environ.get("WIN11_IMAGE_INDEX", "6")
account = ""
firstlogon = ""
if user and password:
    account = f"""
      <LocalAccounts>
        <LocalAccount wcm:action="add">
          <Password><Value>{html.escape(password)}</Value><PlainText>true</PlainText></Password>
          <Description>Local setup administrator</Description>
          <DisplayName>{html.escape(user)}</DisplayName>
          <Group>Administrators</Group>
          <Name>{html.escape(user)}</Name>
        </LocalAccount>
      </LocalAccounts>"""
    firstlogon = "<FirstLogonCommands><SynchronousCommand wcm:action=\"add\"><Order>1</Order><CommandLine>powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\\\\Windows\\\\Temp\\\\Win11-PostInstall.ps1</CommandLine><Description>Siemens post install</Description></SynchronousCommand></FirstLogonCommands>"
oobe = "" if account else "<HideOnlineAccountScreens>false</HideOnlineAccountScreens>"
xml = rf'''<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <SetupUILanguage><UILanguage>de-DE</UILanguage></SetupUILanguage><InputLocale>de-DE</InputLocale><SystemLocale>de-DE</SystemLocale><UILanguage>de-DE</UILanguage><UserLocale>de-DE</UserLocale>
    </component>
    <component name="Microsoft-Windows-PnpCustomizationsWinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <DriverPaths><PathAndCredentials wcm:action="add" wcm:keyValue="1"><Path>.\vioscsi\w11\amd64</Path></PathAndCredentials><PathAndCredentials wcm:action="add" wcm:keyValue="2"><Path>.\NetKVM\w11\amd64</Path></PathAndCredentials></DriverPaths>
    </component>
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <DiskConfiguration><Disk wcm:action="add"><DiskID>0</DiskID><WillWipeDisk>true</WillWipeDisk><CreatePartitions><CreatePartition wcm:action="add"><Order>1</Order><Type>EFI</Type><Size>260</Size></CreatePartition><CreatePartition wcm:action="add"><Order>2</Order><Type>MSR</Type><Size>16</Size></CreatePartition><CreatePartition wcm:action="add"><Order>3</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition></CreatePartitions><ModifyPartitions><ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Format>FAT32</Format><Label>System</Label></ModifyPartition><ModifyPartition wcm:action="add"><Order>2</Order><PartitionID>2</PartitionID></ModifyPartition><ModifyPartition wcm:action="add"><Order>3</Order><PartitionID>3</PartitionID><Format>NTFS</Format><Label>Windows</Label><Letter>C</Letter></ModifyPartition></ModifyPartitions></Disk></DiskConfiguration>
      <ImageInstall><OSImage><InstallFrom><MetaData wcm:action="add"><Key>/IMAGE/INDEX</Key><Value>{html.escape(image_index)}</Value></MetaData></InstallFrom><InstallTo><DiskID>0</DiskID><PartitionID>3</PartitionID></InstallTo><WillShowUI>OnError</WillShowUI></OSImage></ImageInstall>
      <UserData><AcceptEula>true</AcceptEula><ProductKey><Key></Key><WillShowUI>Never</WillShowUI></ProductKey><FullName>Siemens</FullName><Organization>Siemens</Organization><WillShowUI>OnError</WillShowUI></UserData>
    </component>
  </settings>
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"><ComputerName>SIEMENS-WIN11</ComputerName></component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"><OOBE><HideEULAPage>true</HideEULAPage><ProtectYourPC>3</ProtectYourPC>{oobe}</OOBE>{account}{firstlogon}</component>
  </settings>
</unattend>
'''
open(out, "w", encoding="utf-8").write(xml)
PY
  as_root install -d -m 0755 "$MEDIA_CACHE_DIR"
  rm -f "$tmp_iso"
  as_root xorriso -as mkisofs -iso-level 3 -J -R -V WIN11_SUPPORT -o "$tmp_iso" \
    "$answer" "$work/Drivers" "$work/guest-agent" "$work/Win11-PostInstall.ps1" \
    >/dev/null 2>&1 || die "Could not build unattended support ISO"
  as_root mv -f "$tmp_iso" "$SUPPORT_ISO"
  as_root chmod 0644 "$SUPPORT_ISO"
  log "Built unattended support ISO: $SUPPORT_ISO"
}

build_patched_iso() {
  command -v xorriso >/dev/null || die 'xorriso is required for --build-iso.'
  command -v wiminfo >/dev/null || die 'wiminfo (wimlib) is required to inspect install.wim.'
  [[ -f "$ORIGINAL_ISO" ]] || die "Original ISO missing: $ORIGINAL_ISO"
  [[ -f "$PATCHED_WIM" ]] || die "Patched install.wim missing: $PATCHED_WIM"
  local index="$WIN11_IMAGE_INDEX" tmp="$ISO_BUILD_OUTPUT.tmp.$$"
  wiminfo "$PATCHED_WIM" --extract-xml 2>/dev/null | head -1 >/dev/null || true
  log "Patched WIM image index: $index"
  as_root install -d -m 0755 "$(dirname "$ISO_BUILD_OUTPUT")"
  # xorriso replays the original El Torito/GPT boot metadata and replaces only
  # sources/install.wim. No boot image is reconstructed or guessed.
  as_root xorriso -indev "$ORIGINAL_ISO" -outdev "$tmp" \
    -map "$PATCHED_WIM" /sources/install.wim \
    -boot_image any replay -commit >/dev/null
  as_root mv -f "$tmp" "$ISO_BUILD_OUTPUT"
  as_root chmod 0644 "$ISO_BUILD_OUTPUT"
  log "Built patched Windows ISO: $ISO_BUILD_OUTPUT"
}

snapshot_vm_state() {
  [[ "$DISK_BACKEND" == zvol ]] || die '--snapshot/--rollback require WIN11_DISK_BACKEND=zvol.'
  zfs list -H -o name "$ZVOL" >/dev/null 2>&1 || die "ZVOL not found: $ZVOL"
  local state stamp snap dir nvram tpm
  state="$(as_root virsh -c qemu:///system domstate "$VM_NAME" 2>/dev/null | head -1 || true)"
  [[ "$state" == 'shut off' ]] || die "VM must be shut off for snapshot (state: ${state:-unknown})"
  stamp="${SNAPSHOT_NAME:-pre-autopilot-$(date +%Y%m%d-%H%M%S)}"
  snap="${ZVOL}@${stamp}"
  dir="$SNAPSHOT_DIR/$stamp"
  as_root mkdir -p "$dir"
  as_root zfs snapshot "$snap"
  nvram="$(as_root virsh -c qemu:///system dumpxml --inactive "$VM_NAME" | sed -n "s#.*<nvram[^>]*>\([^<]*\)</nvram>.*#\1#p" | head -1)"
  [[ -n "$nvram" && -f "$nvram" ]] || die "NVRAM not found for $VM_NAME"
  as_root cp -a "$nvram" "${nvram}.${stamp}"
  tpm="/var/lib/libvirt/swtpm/$DOMAIN_UUID"
  [[ -d "$tpm" ]] || die "swtpm state directory not found: $tpm"
  as_root cp -a "$tpm" "${tpm}.${stamp}"
  printf '%s\n' "$snap" | as_root tee "$dir/zfs-snapshot" >/dev/null
  log "Snapshot saved: $snap (state: $dir)"
}

rollback_vm_state() {
  [[ "$DISK_BACKEND" == zvol ]] || die '--snapshot/--rollback require WIN11_DISK_BACKEND=zvol.'
  local stamp="${SNAPSHOT_NAME:-}" dir snap nvram tpm
  [[ -n "$stamp" ]] || die '--rollback requires WIN11_SNAPSHOT_NAME=<snapshot-name>'
  dir="$SNAPSHOT_DIR/$stamp"
  [[ -d "$dir" ]] || die "Snapshot state directory missing: $dir"
  snap="$(<"$dir/zfs-snapshot")"
  [[ "$snap" == "$ZVOL@"* ]] || die "Snapshot does not belong to $ZVOL: $snap"
  local state; state="$(as_root virsh -c qemu:///system domstate "$VM_NAME" 2>/dev/null | head -1 || true)"
  [[ "$state" == 'shut off' ]] || die "VM must be shut off for rollback (state: ${state:-unknown})"
  nvram="$(as_root virsh -c qemu:///system dumpxml --inactive "$VM_NAME" | sed -n "s#.*<nvram[^>]*>\([^<]*\)</nvram>.*#\1#p" | head -1)"
  [[ -n "$nvram" ]] || die "NVRAM path unavailable for $VM_NAME"
  as_root zfs rollback -r "$snap"
  [[ -f "${nvram}.${stamp}" ]] || die "NVRAM snapshot missing: ${nvram}.${stamp}"
  as_root cp -a "${nvram}.${stamp}" "$nvram"
  tpm="/var/lib/libvirt/swtpm/$DOMAIN_UUID"
  [[ -d "${tpm}.${stamp}" ]] || die "swtpm snapshot missing: ${tpm}.${stamp}"
  as_root rm -rf "$tpm"
  as_root cp -a "${tpm}.${stamp}" "$tpm"
  log "Rolled back $ZVOL and restored NVRAM/swtpm from $stamp"
}

list_vm_snapshots() {
  zfs list -H -t snapshot -o name,creation,refer \
    | awk -v root="${ZVOL}@" '$1 ~ "^" root {print}'
  find /var/lib/libvirt/qemu/nvram -maxdepth 1 -type f -name "${VM_NAME}_VARS.fd.*" -printf '%f %TY-%Tm-%Td %TH:%TM:%TS %s bytes\n' 2>/dev/null | sort
}

ensure_enrolled_vars_template() {
  [[ "$SECURE_BOOT" == 1 ]] || return 0
  command -v virt-fw-vars >/dev/null || die 'virt-fw-vars is required for enrolled OVMF template.'
  local base="$ENROLLED_VARS_TEMPLATE"
  if [[ ! -f "$base" ]]; then
    as_root install -d -m 0755 "$(dirname "$base")"
    as_root virt-fw-vars -i /usr/share/edk2/x64/OVMF_VARS.4m.fd -o "$base" \
      --enroll-microsoft --microsoft-kek all --microsoft-db all --sb
    as_root chown "$VM_QEMU_USER:$VM_QEMU_USER" "$base"
    as_root chmod 0600 "$base"
  fi
  as_root virt-fw-vars --input "$base" --print --verbose | grep -q '^name=PK ' || die "Enrolled OVMF template has no PK: $base"
}

fresh_install_reset() {
  [[ "$OPERATION_MODE" == fresh-install ]] || return 0
  (( FORCE )) || die 'Refusing destructive VM reset without --force.'
  if (( DRY_RUN )); then
    log "Would remove only the $VM_NAME definition and $DISK_PATH"
    return 0
  fi
  log "Fresh install requested: removing only the $VM_NAME definition and $DISK_PATH"
  if as_root virsh -c qemu:///system dominfo "$VM_NAME" >/dev/null 2>&1; then
    local state
    state="$(as_root virsh -c qemu:///system domstate "$VM_NAME" 2>/dev/null | head -1 || true)"
    if [[ "$state" != "shut off" ]]; then
      as_root virsh -c qemu:///system shutdown "$VM_NAME" >/dev/null 2>&1 || true
      for _ in {1..30}; do
        state="$(as_root virsh -c qemu:///system domstate "$VM_NAME" 2>/dev/null | head -1 || true)"
        [[ "$state" == "shut off" ]] && break
        sleep 1
      done
      [[ "$state" == "shut off" ]] || as_root virsh -c qemu:///system destroy "$VM_NAME"
    fi
    # This mode is an explicitly requested complete rebuild. Preserve a
    # forensic copy, then let virt-install create a new per-VM NVRAM store;
    # ensure_secure_boot_keys() enrolls Microsoft keys before first boot.
    local old_nvram
    old_nvram="$(as_root virsh -c qemu:///system dumpxml "$VM_NAME" 2>/dev/null | sed -n 's#.*<nvram[^>]*>\([^<]*\)</nvram>.*#\1#p' | head -1)"
    if [[ -n "$old_nvram" && -f "$old_nvram" ]]; then
      as_root cp -a "$old_nvram" "${old_nvram}.before-fresh-$(date +%Y%m%d-%H%M%S)"
    fi
    as_root virsh -c qemu:///system undefine "$VM_NAME" --nvram
  fi
  if [[ "$DISK_BACKEND" == qcow2 ]]; then
    [[ -e "$DISK_PATH" ]] && as_root rm -f -- "$DISK_PATH"
    return 0
  fi
  if zfs list -H -o name "$ZVOL" >/dev/null 2>&1; then
    # A forensic snapshot/clone can keep the volume busy.  Fresh-install is
    # explicitly destructive, so remove dependents only in this mode; normal
    # reruns retain the VM and all snapshots.
    local dependents snapshots
    snapshots="$(as_root zfs list -H -t snapshot -o name 2>/dev/null | awk -v root="$ZVOL@" 'index($0, root) == 1 {print}')"
    if [[ -n "$snapshots" ]]; then
      log "Removing dependent ZFS snapshots for destructive fresh install: $snapshots"
      while IFS= read -r snapshot; do
        [[ -n "$snapshot" ]] || continue
        as_root zfs destroy -f "$snapshot"
      done <<< "$snapshots"
    fi
    dependents="$(as_root zfs list -H -t filesystem,volume -o name,origin 2>/dev/null | awk -v root="$ZVOL" '$2 != "-" && index($2, root "@") == 1 {print $1}')"
    if [[ -n "$dependents" ]]; then
      log "Removing dependent ZFS clones/snapshots for destructive fresh install: $dependents"
      while IFS= read -r dependent; do
        [[ -n "$dependent" ]] || continue
        as_root zfs unmount -f "$dependent" >/dev/null 2>&1 || true
        # Partition mounts of a ZVOL (for example a read-only forensic ESP or
        # NTFS mount) are outside ZFS and otherwise keep the clone busy.
        local zvol_dev
        zvol_dev="$(readlink -f "/dev/zvol/$dependent" 2>/dev/null || true)"
        if [[ -n "$zvol_dev" && -x "$(command -v findmnt 2>/dev/null || true)" ]]; then
          while IFS= read -r mountpoint; do
            [[ -n "$mountpoint" ]] || continue
            as_root umount -l "$mountpoint" >/dev/null 2>&1 || true
          done < <(findmnt -rn -o SOURCE,TARGET | awk -v dev="$zvol_dev" '$1 == dev || index($1, dev "p") == 1 {print $2}')
        fi
      done <<< "$dependents"
      as_root zfs destroy -R -f "$ZVOL"
    else
      as_root zfs destroy -f "$ZVOL"
    fi
  fi
}

resolve_pci_hostdev() {
  if [[ "$DISABLE_PCI_PASSTHROUGH" == 1 ]]; then
    [[ -z "$PCI_HOSTDEV_BDF" && -z "$PCI_HOSTDEV_IFACE" && "$PCI_HOSTDEV_AUTO" != 1 ]] ||
      die 'PCI passthrough is disabled for this VM profile.'
    PCI_HOSTDEV_BDF=""
    PCI_HOSTDEV_IFACE=""
    PCI_HOSTDEV_AUTO=0
    return 0
  fi
  [[ -n "$PCI_HOSTDEV_BDF" || "$PCI_HOSTDEV_AUTO" == 1 ]] || return 0
  if [[ -z "$PCI_HOSTDEV_BDF" ]]; then
    local iface addr candidate
    while IFS= read -r iface; do
      [[ -e "/sys/class/net/$iface/device" ]] || continue
      addr="$(cat "/sys/class/net/$iface/address" 2>/dev/null || true)"
      [[ "${addr,,}" == "${PCI_HOSTDEV_MAC,,}" ]] || continue
      candidate="$(basename "$(readlink -f "/sys/class/net/$iface/device")")"
      [[ "$candidate" =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F]+$ ]] || continue
      PCI_HOSTDEV_BDF="$candidate"
      PCI_HOSTDEV_IFACE="$iface"
      break
    done < <(find /sys/class/net -mindepth 1 -maxdepth 1 -printf '%f\n')
  fi
  [[ -n "$PCI_HOSTDEV_BDF" ]] || die "Could not resolve PCI host device from MAC $PCI_HOSTDEV_MAC"
  if [[ -z "$PCI_HOSTDEV_IFACE" ]]; then
    PCI_HOSTDEV_IFACE="$(find "/sys/bus/pci/devices/$PCI_HOSTDEV_BDF/net" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | head -1)"
  fi
  [[ -n "$PCI_HOSTDEV_IFACE" ]] || die "Could not resolve host interface for PCI device $PCI_HOSTDEV_BDF"
  log "Resolved PCI passthrough: $PCI_HOSTDEV_BDF -> $PCI_HOSTDEV_IFACE (MAC $PCI_HOSTDEV_MAC)"
}

create_disk() {
  if [[ "$DISK_BACKEND" == qcow2 ]]; then
    command -v qemu-img >/dev/null || die 'qemu-img is required for the qcow2 backend.'
    if [[ -e "$DISK_PATH" ]]; then
      log "Existing QCOW2 retained: $DISK_PATH"
    else
      as_root install -d -m 0755 "$(dirname "$DISK_PATH")"
      as_root qemu-img create -f qcow2 -o preallocation=metadata "$DISK_PATH" "$VOLSIZE"
      as_root chown "$VM_QEMU_USER:$VM_QEMU_USER" "$DISK_PATH" 2>/dev/null || true
    fi
    return 0
  fi
  zpool list -H -o name "$POOL" >/dev/null 2>&1 || die "ZFS pool not found: $POOL"
  zfs list -H -o name "${POOL}/vms" >/dev/null 2>&1 || as_root zfs create -o mountpoint=none -o "atime=$ZFS_ATIME" "${POOL}/vms"
  if zfs list -H -o name "$ZVOL" >/dev/null 2>&1; then
    log "Existing ZVOL retained; volblocksize is immutable after creation."
  else
    local sparse=()
    [[ "$ZVOL_SPARSE" == 1 ]] && sparse=(-s)
    as_root zfs create "${sparse[@]}" -V "$VOLSIZE" -b "$ZVOL_VOLBLOCKSIZE" \
      -o "compression=$ZFS_COMPRESSION" -o "sync=$ZFS_SYNC" \
      -o "primarycache=$ZFS_PRIMARYCACHE" -o volmode=dev "$ZVOL"
  fi
}

define_vm() {
  if (( DRY_RUN )); then
    log "Would define $VM_NAME with explicit SMBIOS serial=$SMBIOS_SERIAL, disk serial=$DISK_SERIAL, MAC=$MAC"
    log "Would use $SCSI_MODEL/$DISK_BUS, cache=$CACHE_MODE, io=$IO_MODE, discard=$DISCARD_MODE, compression=$ZFS_COMPRESSION, sparse=$ZVOL_SPARSE and ${HUGEPAGES} hugepages"
    return 0
  fi
  command -v virt-install >/dev/null || die 'virt-install is required.'
  local xml; xml="$(mktemp)"; trap 'rm -f "$xml"' RETURN
  local memory_args=()
  (( USE_HUGEPAGES )) && memory_args=(--memorybacking hugepages=yes)
  local disk_boot="" iso_boot=""
  if [[ "$BOOT_FROM_ISO" == 1 ]]; then
    disk_boot=",boot.order=2"
    iso_boot=",boot.order=1"
  fi
  local nvram_path="/var/lib/libvirt/qemu/nvram/${VM_NAME}_VARS.fd"
  local ovmf_code="/usr/share/edk2/x64/OVMF_CODE.4m.fd"
  [[ "$SECURE_BOOT" == 1 ]] && ovmf_code="/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd"
  local ovmf_vars="$ENROLLED_VARS_TEMPLATE"
  local media_args=(--disk "path=$WIN11_ISO_PATH,device=cdrom,readonly=on$iso_boot" --disk "path=$VIRTIO_ISO_PATH,device=cdrom,readonly=on")
  [[ -f "$SUPPORT_ISO" ]] && media_args+=(--disk "path=$SUPPORT_ISO,device=cdrom,readonly=on")
  [[ -f "$ovmf_code" ]] || die "Secure-Boot OVMF code missing: $ovmf_code"
  [[ -f "$ovmf_vars" ]] || die "OVMF variable template missing: $ovmf_vars"
  virt_args=(virt-install --connect qemu:///system --name "$VM_NAME" --uuid "$DOMAIN_UUID" --memory "$RAM_MIB" \
    --vcpus "$VCPUS,sockets=$CPU_SOCKETS,cores=$CPU_CORES,threads=$CPU_THREADS" --cpu "$CPU_MODE,migratable=off" "${memory_args[@]}" \
    --controller "type=scsi,model=$SCSI_MODEL" \
    --disk "path=$DISK_PATH,format=$([[ "$DISK_BACKEND" == qcow2 ]] && echo qcow2 || echo raw),device=disk,bus=$DISK_BUS,cache=$CACHE_MODE,io=$IO_MODE,discard=$DISCARD_MODE,detect_zeroes=$DETECT_ZEROES,serial=$DISK_SERIAL$disk_boot" \
    "${media_args[@]}" \
    --network "network=default,model=$NETWORK_MODEL,mac=$MAC" --osinfo "$OS_VARIANT" \
    --boot "loader=$ovmf_code,loader.readonly=yes,loader.type=pflash,nvram=$nvram_path,nvram.template=$ovmf_vars,menu=off" \
    --tpm "default,model=$TPM_MODEL" \
    --features smm.state=on --graphics "$GRAPHICS_TYPE,streaming.mode=$SPICE_STREAMING_MODE,image.compression=$SPICE_IMAGE_COMPRESSION" \
    --memballoon none --watchdog none \
    --check path_in_use=off,mac_in_use=off \
    --video "$VIDEO_MODEL" --noautoconsole --noreboot --dry-run --print-xml)
  if (( EUID == 0 )); then "${virt_args[@]}" > "$xml"; else sudo "${virt_args[@]}" > "$xml"; fi
  sed -i "s#</domain>#<sysinfo type='smbios'><system><entry name='manufacturer'>QEMU</entry><entry name='product'>KVM Windows 11</entry><entry name='serial'>$SMBIOS_SERIAL</entry></system></sysinfo></domain>#" "$xml"
  # Keep firmware boot deterministic: the original Windows ISO is the only
  # bootable CD; VirtIO/support media are data CDs and must never win boot.
  BOOT_FROM_ISO="$BOOT_FROM_ISO" WIN11_PCI_HOSTDEV_BDF="$PCI_HOSTDEV_BDF" \
    WIN11_NETWORK_LINK_STATE="$NETWORK_LINK_STATE" WIN11_GUEST_AGENT="${WIN11_GUEST_AGENT:-0}" python3 - "$xml" <<'PY'
import sys
import os
from xml.etree import ElementTree as ET
path = sys.argv[1]
root = ET.parse(path).getroot()
cpu_node = root.find('cpu')
if cpu_node is not None:
    cpu_node.set('migratable', 'off')
# Preserve the known-good Hyper-V set from the existing VM, but probe each
# optional feature with QEMU before emitting it. A trial QEMU process is
# daemonized only for validation and immediately terminated.
import subprocess, tempfile, signal, time
hyperv = root.find('features/hyperv')
if hyperv is not None:
    for feature in list(hyperv):
        if feature.tag == 'spinlocks':
            prop = 'hv-spinlocks=0x1fff'
        else:
            prop = 'hv-' + feature.tag.replace('_', '-') + '=on'
        with tempfile.NamedTemporaryFile(prefix='win11-hv-probe-', delete=False) as f:
            pidfile = f.name
        os.unlink(pidfile)
        try:
            probe = subprocess.run(['qemu-system-x86_64', '-machine', 'q35,accel=kvm', '-cpu', 'host,' + prop,
                '-nodefaults', '-display', 'none', '-S', '-daemonize', '-pidfile', pidfile],
                capture_output=True, text=True, timeout=8)
            if probe.returncode:
                hyperv.remove(feature)
            else:
                try:
                    pid = int(open(pidfile).read().strip())
                    os.kill(pid, signal.SIGTERM)
                except (OSError, ValueError):
                    pass
        except (subprocess.TimeoutExpired, OSError):
            hyperv.remove(feature)
        finally:
            try: os.unlink(pidfile)
            except OSError: pass
    if not list(hyperv):
        root.find('features').remove(hyperv)
devices = root.find('devices')
os_node = root.find('os')
# Keep the explicit, stable per-VM OVMF code/NVRAM paths.  This host's
# libvirt firmware capabilities expose enrolledKeys=no, so the XML feature is
# not a request for key enrollment; ensure_secure_boot_keys() enrolls and
# verifies the Microsoft keys directly in the per-VM NVRAM below.
balloon = root.find('devices/memballoon')
if balloon is not None:
    balloon.set('model', 'none')
watchdog = root.find('devices/watchdog')
if watchdog is not None:
    watchdog.set('action', 'none')
    if watchdog.get('model') is None:
        watchdog.set('model', 'itco')
else:
    ET.SubElement(root.find('devices'), 'watchdog', {'model':'itco', 'action':'none'})
for channel in list(root.findall('devices/channel')):
    target = channel.find('target')
    if target is not None and target.get('name') == 'org.qemu.guest_agent.0':
        root.find('devices').remove(channel)
if os.environ.get('WIN11_GUEST_AGENT') == '1':
    channel = ET.SubElement(devices, 'channel', {'type': 'unix'})
    source = ET.SubElement(channel, 'source', {'mode': 'bind'})
    ET.SubElement(channel, 'target', {'type': 'virtio', 'name': 'org.qemu.guest_agent.0'})
    ET.SubElement(channel, 'address', {'type': 'virtio-serial', 'controller': '0', 'bus': '0', 'port': '1'})
# Explicit pflash loader/NVRAM paths are authoritative. Remove automatic
# firmware policy and firmware feature blocks from the generated XML.
if os_node is not None:
    loader = os_node.find('loader')
    if loader is not None and os.environ.get('WIN11_SECURE_BOOT', '1') == '1':
        loader.set('secure', 'yes')
    os_node.attrib.pop('firmware', None)
    firmware = os_node.find('firmware')
    if firmware is not None:
        os_node.remove(firmware)
hostdev_bdf = os.environ.get('WIN11_PCI_HOSTDEV_BDF', '')
if hostdev_bdf:
    # Replace the virtual NIC with the physical PCI NIC for the passthrough VM.
    devices = root.find('devices')
    for interface in list(devices.findall('interface')):
        devices.remove(interface)
    parts = hostdev_bdf.replace('0000:', '').replace('.', ':').split(':')
    if len(parts) != 3:
        raise SystemExit('Invalid PCI BDF: ' + hostdev_bdf)
    bus, slot, function = parts
    hostdev = ET.SubElement(devices, 'hostdev', {'mode':'subsystem', 'type':'pci', 'managed':'yes'})
    source = ET.SubElement(hostdev, 'source')
    ET.SubElement(source, 'address', {'domain':'0x0000', 'bus':'0x'+bus, 'slot':'0x'+slot, 'function':'0x'+function})
network_link_state = os.environ.get('WIN11_NETWORK_LINK_STATE', '')
if network_link_state in ('up', 'down'):
    for interface in devices.findall('interface'):
        link = interface.find('link')
        if link is None:
            link = ET.SubElement(interface, 'link')
        link.set('state', network_link_state)
if os.environ.get('BOOT_FROM_ISO') != '1':
    os_node = root.find('os')
    if os_node is not None:
        for old in list(os_node.findall('boot')):
            os_node.remove(old)
for disk in root.findall('devices/disk'):
    if disk.get('device') not in ('disk', 'cdrom'):
        continue
    target = disk.find('target')
    if target is None:
        continue
    for old in list(disk.findall('boot')):
        disk.remove(old)
    dev = target.get('dev')
    if dev == 'sdb' and os.environ.get('BOOT_FROM_ISO') == '1':
        ET.SubElement(disk, 'boot', {'order': '1'})
    elif dev == 'sda':
        ET.SubElement(disk, 'boot', {'order': '2' if os.environ.get('BOOT_FROM_ISO') == '1' else '1'})
ET.ElementTree(root).write(path, encoding='utf-8', xml_declaration=True)
PY
  if as_root virsh -c qemu:///system dominfo "$VM_NAME" >/dev/null 2>&1; then
    if [[ "$(as_root virsh -c qemu:///system domstate "$VM_NAME" 2>/dev/null | head -1)" != "shut off" ]]; then
      log "VM $VM_NAME is already running; retaining its active definition"
      return 0
    fi
    log "Updating existing inactive definition: $VM_NAME"
  fi
  as_root virsh -c qemu:///system define "$xml"
  # Re-read and sanitize the persistent XML so the ballooning policy survives
  # libvirt daemon defaults and subsequent restarts. This host may retain its
  # platform watchdog even when virt-install requests --watchdog none.
  local defined_xml; defined_xml="$(mktemp)"
  as_root virsh -c qemu:///system dumpxml --inactive "$VM_NAME" > "$defined_xml"
  python3 - "$defined_xml" <<'PY'
import sys
from xml.etree import ElementTree as ET
path = sys.argv[1]
tree = ET.parse(path)
root = tree.getroot()
devices = root.find('devices')
if devices is not None:
    # libvirt may add its platform watchdog back while defining a Q35 guest;
    # retain that daemon default because this host rejects model=none.
    balloon = devices.find('memballoon')
    if balloon is None:
        ET.SubElement(devices, 'memballoon', {'model': 'none'})
    else:
        balloon.set('model', 'none')
    watchdog = devices.find('watchdog')
    if watchdog is None:
        watchdog = ET.SubElement(devices, 'watchdog', {'model':'itco'})
    watchdog.set('action', 'none')
tree.write(path, encoding='utf-8', xml_declaration=True)
PY
  as_root virsh -c qemu:///system define "$defined_xml" >/dev/null
  rm -f "$defined_xml"
}

start_vm() {
  [[ "$START_VM" == 1 ]] || { log "VM start disabled (WIN11_START_VM=$START_VM)"; return 0; }
  local state
  state="$(as_root virsh -c qemu:///system domstate "$VM_NAME" 2>/dev/null | head -1 || true)"
  case "$state" in
    running|paused) log "VM already active: $VM_NAME ($state)" ;;
    *)
      if [[ -n "$PCI_HOSTDEV_BDF" ]]; then
        prepare_pci_hostdev
      fi
      if ! as_root virsh -c qemu:///system start "$VM_NAME"; then
        log 'VM start failed; restoring the host PCI device and connection.'
        "$SCRIPT_DIR/win11-pci-passthrough-undo.sh" "$PCI_HOSTDEV_BDF" "$PCI_HOSTDEV_IFACE" "$PCI_HOSTDEV_CONNECTION" || true
        return 1
      fi
      if [[ -n "$PCI_HOSTDEV_BDF" && "$PCI_WATCHER_ENABLED" == 1 ]]; then
        start_pci_restore_watcher
      fi
      if [[ "$OPERATION_MODE" == fresh-install && "$BOOT_FROM_ISO" == 1 ]]; then
        # Windows El Torito images wait for a key; feed it once so a fresh run
        # does not require a viewer or manual console interaction.
        sleep 5
        as_root virsh -c qemu:///system qemu-monitor-command "$VM_NAME" --hmp 'sendkey ret' >/dev/null 2>&1 || true
      fi
      ;;
  esac
}

prepare_pci_hostdev() {
  local node="$PCI_HOSTDEV_BDF" conn fallback
  node="pci_${node//:/_}"; node="${node//./_}"
  [[ -n "$PCI_HOSTDEV_IFACE" ]] || die 'WIN11_PCI_HOSTDEV_IFACE is required for PCI passthrough.'
  ip link show "$PCI_HOSTDEV_IFACE" >/dev/null 2>&1 || die "Host NIC not found: $PCI_HOSTDEV_IFACE"
  if [[ -z "$PCI_HOSTDEV_CONNECTION" ]]; then
    conn="$(nmcli -g GENERAL.CONNECTION device show "$PCI_HOSTDEV_IFACE" 2>/dev/null || true)"
    [[ "$conn" != "--" ]] && PCI_HOSTDEV_CONNECTION="$conn"
  fi
  if [[ -z "$PCI_HOSTDEV_FALLBACK_IFACE" ]]; then
    fallback="$(nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null \
      | awk -F: -v target="$PCI_HOSTDEV_IFACE" '$1 != target && $3 == "connected" && ($2 == "wifi" || $2 == "ethernet") {print $1; exit}')"
    PCI_HOSTDEV_FALLBACK_IFACE="$fallback"
  fi
  [[ -n "$PCI_HOSTDEV_FALLBACK_IFACE" ]] || die "Refusing PCI passthrough: no connected host fallback interface found (target=$PCI_HOSTDEV_IFACE)."
  log "Host fallback interface: $PCI_HOSTDEV_FALLBACK_IFACE"
  nmcli -t -f DEVICE,STATE device status 2>/dev/null | awk -F: -v fallback="$PCI_HOSTDEV_FALLBACK_IFACE" '$1 == fallback && $2 == "connected" {ok=1} END {exit ok ? 0 : 1}' || die "Refusing PCI passthrough: fallback interface is not connected: $PCI_HOSTDEV_FALLBACK_IFACE"
  [[ -d /sys/module/vfio ]] || die 'PCI passthrough unavailable: vfio kernel module is not loaded; enable IOMMU and reboot first.'
  [[ -d /sys/kernel/iommu_groups ]] && find /sys/kernel/iommu_groups -mindepth 1 -maxdepth 1 -type d -print -quit | grep -q . || die 'PCI passthrough unavailable: no active IOMMU groups; enable intel_iommu=on or amd_iommu=on and reboot.'
  log "Detaching host Ethernet $PCI_HOSTDEV_IFACE ($PCI_HOSTDEV_BDF) for $VM_NAME"
  [[ -n "$PCI_HOSTDEV_CONNECTION" ]] && nmcli connection down "$PCI_HOSTDEV_CONNECTION" >/dev/null 2>&1 || nmcli device disconnect "$PCI_HOSTDEV_IFACE" >/dev/null 2>&1 || true
  as_root virsh -c qemu:///system nodedev-detach "$node" >/dev/null 2>&1 || true
}

start_pci_restore_watcher() {
  local watcher="$SCRIPT_DIR/win11-pci-passthrough-watch.sh"
  [[ -x "$watcher" ]] || die "Missing passthrough watcher: $watcher"
  nohup "$watcher" "$VM_NAME" "$PCI_HOSTDEV_BDF" "$PCI_HOSTDEV_IFACE" "$PCI_HOSTDEV_CONNECTION" \
    >"/tmp/${VM_NAME}-pci-passthrough-watch.log" 2>&1 < /dev/null &
  log "PCI passthrough restore watcher started for $VM_NAME"
}

ensure_secure_boot_keys() {
  [[ "$SECURE_BOOT" == 1 ]] || { log 'Secure Boot disabled; skipping OVMF key enrollment.'; return 0; }
  (( ENROLL_SECURE_BOOT_KEYS )) || return 0
  command -v virt-fw-vars >/dev/null || { log 'virt-fw-vars unavailable; leaving OVMF NVRAM unchanged'; return 0; }
  local nvram loader state
  state="$(as_root virsh -c qemu:///system domstate "$VM_NAME" 2>/dev/null | head -1 || true)"
  [[ "$state" == "shut off" ]] || { log "VM is $state; refusing to modify OVMF NVRAM while active"; return 0; }
  loader="$(as_root virsh -c qemu:///system dumpxml "$VM_NAME" | sed -n "s#.*<loader[^>]*>\([^<]*\)</loader>.*#\1#p" | head -1)"
  [[ "$loader" == *secboot* ]] || { log 'Secure-Boot loader not active; skipping key enrollment'; return 0; }
  local template
  nvram="$(as_root virsh -c qemu:///system dumpxml "$VM_NAME" | awk -F'[<>]' '/<nvram / {print $3; exit}')"
  template="$(as_root virsh -c qemu:///system dumpxml "$VM_NAME" | sed -n "s#.*<nvram[^>]*template='\([^']*\)'.*#\1#p" | head -1)"
  if [[ -n "$nvram" && ! -f "$nvram" && -f "$template" ]]; then
    log "Creating per-VM OVMF NVRAM from template: $nvram"
    as_root install -o "$VM_QEMU_USER" -g "$VM_QEMU_USER" -m 0600 "$template" "$nvram"
  fi
  [[ -n "$nvram" && -f "$nvram" ]] || { log 'Per-VM OVMF NVRAM not found; skipping key enrollment'; return 0; }
  if ! as_root virt-fw-vars --input "$nvram" --print --verbose 2>/dev/null | grep -q '^name=PK '; then
    log "Enrolling Microsoft Secure-Boot 2011/2023 keys in $nvram"
    as_root cp -a "$nvram" "${nvram}.before-microsoft-keys"
    as_root virt-fw-vars --in-place "$nvram" --enroll-microsoft --microsoft-db all --microsoft-kek all --sb
  else
    log "Microsoft Secure-Boot PK already present in $nvram"
  fi
}

verify_vm() {
  local xml secure enrolled tpm disk net cpu machine mem vcpus nvram nvram_template keylines network_desc io_line balloon watchdog migratable hostdev
  xml="$(as_root virsh -c qemu:///system dumpxml "$VM_NAME")"
  hostdev="$(grep -c "<hostdev mode='subsystem' type='pci'" <<< "$xml" || true)"
  [[ "$DISABLE_PCI_PASSTHROUGH" != 1 || "$hostdev" == 0 ]] || die 'VM verification failed: PCI hostdev present in a no-passthrough profile.'
  secure="$(grep -q "<loader[^>]*secure='yes'" <<< "$xml" && echo yes || echo no)"
  tpm="$(grep -q "<tpm model='tpm-crb'" <<< "$xml" && echo yes || echo no)"
  disk="$(grep -E -q "<target dev='sda' bus='$DISK_BUS'" <<< "$xml" && echo "$DISK_BUS" || echo unknown)"
  if [[ -n "$PCI_HOSTDEV_BDF" ]]; then
    net="$(grep -q "<hostdev mode='subsystem' type='pci'" <<< "$xml" && echo passthrough || echo missing)"
    network_desc="PCI passthrough $PCI_HOSTDEV_BDF"
  else
    net="$(grep -q "<link state='down'" <<< "$xml" && echo down || echo up)"
    network_desc="$NETWORK_MODEL link=$net"
  fi
  cpu="$(sed -n "s/.*<cpu[^>]*mode='\([^']*\)'.*/\1/p" <<< "$xml" | head -1)"
  vcpus="$(sed -n "s/.*<vcpu[^>]*>\([^<]*\).*/\1/p" <<< "$xml" | head -1)"
  machine="$(sed -n "s/.*machine='\([^']*\)'.*/\1/p" <<< "$xml" | head -1)"
  mem="$(awk -F'[<>]' '/<memory unit=/ {v=$3; if ($0 ~ /unit=\x27KiB\x27/) v=int(v/1024); print v; exit}' <<< "$xml")"
  nvram="$(awk -F'[<>]' '/<nvram / {print $3; exit}' <<< "$xml")"
  nvram_template="$(sed -n "s#.*<nvram[^>]*template='\([^']*\)'.*#\1#p" <<< "$xml" | head -1)"
  keylines="$(as_root virt-fw-vars --input "$nvram" --print --verbose 2>/dev/null | grep -E '^name=(PK|KEK|db) ' || true)"
  enrolled="$(printf '%s' "$keylines" | grep -q '^name=PK ' && printf yes || printf no)"
  io_line="$(grep -E "<driver[^>]*(cache='$CACHE_MODE'|io='$IO_MODE')" <<< "$xml" | head -1 || true)"
  balloon="$(grep -q "<memballoon model='none'" <<< "$xml" && echo none || echo present)"
  watchdog="$(grep -q '<watchdog ' <<< "$xml" && echo present || echo none)"
  local smbios_manufacturer smbios_product smbios_serial disk_serial link_state
  smbios_manufacturer="$(sed -n "s#.*<entry name='manufacturer'>\([^<]*\)</entry>.*#\1#p" <<< "$xml" | head -1)"
  smbios_product="$(sed -n "s#.*<entry name='product'>\([^<]*\)</entry>.*#\1#p" <<< "$xml" | head -1)"
  smbios_serial="$(sed -n "s#.*<entry name='serial'>\([^<]*\)</entry>.*#\1#p" <<< "$xml" | head -1)"
  disk_serial="$(sed -n "s#.*<disk[^>]*device='disk'.*<serial>\([^<]*\)</serial>.*#\1#p" <<< "$xml" | head -1)"
  link_state="$(grep -o "<link state='[^']*'" <<< "$xml" | head -1 | sed "s/.*state='//; s/'//")"
  migratable="$(sed -n "s/.*<cpu[^>]*migratable='\([^']*\)'.*/\1/p" <<< "$xml" | head -1)"
  local expected_secure=no expected_enrolled=no
  [[ "$SECURE_BOOT" == 1 ]] && expected_secure=yes && expected_enrolled=yes
  [[ "$secure" == "$expected_secure" && "$tpm" == yes && "$disk" == "$DISK_BUS" && "$cpu" == host-passthrough && "$migratable" == off && "$machine" == pc-q35-11.1 && "$mem" == 16384 && "$vcpus" == "$VCPUS" ]] || die 'VM verification failed; see values above.'
  [[ "$SECURE_BOOT" != 1 || "$nvram_template" == "$ENROLLED_VARS_TEMPLATE" ]] || die 'VM verification failed: unenrolled OVMF template is still configured.'
  [[ "$SECURE_BOOT" != 1 || "$enrolled" == "$expected_enrolled" ]] || die 'Secure-Boot key state verification failed.'
  [[ "$net" == up || "$net" == down || "$net" == passthrough ]] || die 'VM network verification failed; see values above.'
  if [[ "$SECURE_BOOT" == 1 ]]; then
    [[ "$keylines" == *'name=PK '* && "$keylines" == *'name=KEK '* && "$keylines" == *'name=db '* ]] || die 'Secure-Boot key verification failed.'
  fi
  [[ "$io_line" == *"cache='$CACHE_MODE'"* && "$io_line" == *"io='$IO_MODE'"* ]] || die 'VM disk I/O verification failed; see values above.'
  [[ "$balloon" == none ]] || die 'Unwanted balloon device found.'
  [[ "$watchdog" == present ]] || die 'VM verification failed: watchdog is missing.'
  grep -q "<watchdog[^>]*action='none'" <<< "$xml" || die 'VM verification failed: watchdog action is not none.'
  [[ "$smbios_manufacturer" == QEMU && "$smbios_product" == 'KVM Windows 11' && "$smbios_serial" == "$SMBIOS_SERIAL" ]] || die 'VM verification failed: SMBIOS identity mismatch.'
  grep -q "<serial>$DISK_SERIAL</serial>" <<< "$xml" || die 'VM verification failed: disk serial mismatch.'
  [[ -z "$NETWORK_LINK_STATE" || "$link_state" == "$NETWORK_LINK_STATE" ]] || die 'VM verification failed: network link state mismatch.'
  log "Verification: Q35/KVM machine=$machine RAM=${mem}MiB CPU=$cpu vCPUs=$vcpus migratable=$migratable"
  log "Verification: Secure Boot=$secure, Enrolled Keys=$enrolled (PK/KEK/db; Microsoft 2011+2023 enrollment), TPM=tpm-crb"
  log "Verification: NVRAM=$nvram, Disk=$disk, cache=$CACHE_MODE, io=$IO_MODE, discard=$DISCARD_MODE, Network=$network_desc, PCI-hostdev=$hostdev"
}

if [[ "$MODE" == check ]]; then
  check_host
  exit $?
fi
if [[ "$MODE" == build-iso ]]; then
  build_patched_iso
  exit 0
fi
if [[ "$MODE" == verify ]]; then
  verify_vm
  exit 0
fi
if [[ "$MODE" == start ]]; then
  start_vm
  exit 0
fi
if [[ "$MODE" == snapshot ]]; then
  [[ "$SNAPSHOT_NAME" == list ]] && { list_vm_snapshots; exit 0; }
  [[ -n "$SNAPSHOT_NAME" ]] || die 'snapshot requires a name (or: snapshot list)'
  snapshot_vm_state
  exit 0
fi
if [[ "$MODE" == rollback ]]; then
  rollback_vm_state
  exit 0
fi
if [[ "$MODE" == prepare ]]; then
  install_packages
  enable_libvirt
  ensure_default_network
  ensure_vm_firewall
  download_media
  stage_media
  build_install_iso
  log 'Preparation complete; running prerequisite check.'
  check_host
  exit $?
fi
if [[ "$MODE" == dry ]]; then
  install_packages
  enable_libvirt
  ensure_default_network
  ensure_vm_firewall
  download_media
  stage_media
  build_install_iso
fi
if [[ "$MODE" == install ]]; then
  check_host || die 'Preparation check failed; run --prepare first.'
  if [[ "$REQUIRE_PATCHED_ISO" == 1 ]]; then
    [[ -f "$ISO_BUILD_OUTPUT" ]] || die "Patched ISO required before install: $ISO_BUILD_OUTPUT (run --build-iso first)"
    [[ "$WIN11_ISO_PATH" == "$ISO_BUILD_OUTPUT" ]] || die "Install is locked to patched ISO: $ISO_BUILD_OUTPUT"
  fi
  # Re-resolve removable-media paths to the staged libvirt copies before the
  # VM XML is generated; the external mount is not a valid QEMU data source.
  stage_media
fi
fresh_install_reset
resolve_pci_hostdev
if [[ "$OPERATION_MODE" == fresh-install && -z "${WIN11_BOOT_FROM_ISO:-}" ]]; then
  BOOT_FROM_ISO=1
fi
reserve_hugepages
create_disk
ensure_enrolled_vars_template
define_vm
ensure_secure_boot_keys
if [[ "$SNAPSHOT_BEFORE_START" == 1 && "$DISK_BACKEND" == zvol ]]; then
  snapshot_vm_state
fi
start_vm
(( DRY_RUN )) && { log 'Dry-run complete; no VM changes were applied.'; exit 0; }
verify_vm
log "Done. VM state: $(as_root virsh -c qemu:///system domstate "$VM_NAME" | head -1)"

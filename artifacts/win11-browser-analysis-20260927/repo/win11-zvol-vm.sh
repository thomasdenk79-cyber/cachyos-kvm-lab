#!/usr/bin/env bash
set -Eeuo pipefail

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
NETWORK_LINK_STATE="${WIN11_NETWORK_LINK_STATE:-up}" # set down to prevent OOBE ZDP updates
[[ "$NETWORK_LINK_STATE" == up || "$NETWORK_LINK_STATE" == down ]] || die "WIN11_NETWORK_LINK_STATE must be up or down"

# ZFS/ZVOL: fixed provisioning is the default for predictable latency and to
# avoid pool ENOSPC during a VM write burst. Set ZVOL_SPARSE=1 to test a thin
# (dynamic) ZVOL; thin provisioning saves space but needs free-space monitoring.
POOL="${WIN11_ZFS_POOL:-zpcachyos}"
ZVOL="${WIN11_ZVOL:-${POOL}/vms/win11}"
VOLSIZE="${WIN11_VOLSIZE:-200G}"
ZVOL_SPARSE="${WIN11_ZVOL_SPARSE:-0}"       # 0=fixed, 1=dynamic/thin
ZVOL_VOLBLOCKSIZE="${WIN11_VOLBLOCKSIZE:-64K}" # good NTFS/KVM compromise
ZFS_COMPRESSION="${WIN11_COMPRESSION:-off}" # avoid host compression work for VM blocks
ZFS_SYNC="${WIN11_SYNC:-standard}"          # durability; disabled is benchmark-only
ZFS_PRIMARYCACHE="${WIN11_PRIMARYCACHE:-metadata}" # avoid double-caching guest filesystem data
ZFS_ATIME="${WIN11_ATIME:-off}"
ZVOL_DEV="/dev/zvol/${ZVOL}"

# Guest CPU/RAM: host-passthrough and 1x8x1 expose the real CPU efficiently.
RAM_MIB="${WIN11_RAM_MIB:-16384}"
VCPUS="${WIN11_VCPUS:-8}"
CPU_MODE="${WIN11_CPU_MODE:-host-passthrough}"
CPU_SOCKETS="${WIN11_CPU_SOCKETS:-1}"
CPU_CORES="${WIN11_CPU_CORES:-8}"
CPU_THREADS="${WIN11_CPU_THREADS:-1}"
HUGEPAGES="${WIN11_HUGEPAGES:-8192}"        # 8192 * 2MiB = 16GiB VM RAM
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
AUTOATTEND="${WIN11_AUTOATTEND:-1}"
WIN11_IMAGE_INDEX="${WIN11_IMAGE_INDEX:-6}" # Windows 11 Pro in the standard multi-edition ISO
REMASTERED_ISO="${WIN11_REMASTERED_ISO:-$MEDIA_CACHE_DIR/${VM_NAME}-install.iso}"
SUPPORT_ISO="${WIN11_SUPPORT_ISO:-$MEDIA_CACHE_DIR/${VM_NAME}-support.iso}"
VM_QEMU_USER="${WIN11_QEMU_USER:-libvirt-qemu}" # used for optional ACLs
VM_ADMIN_USER="${WIN11_ADMIN_USER:-${SUDO_USER:-$USER}}"
VM_ADMIN_GROUPS=(libvirt kvm)                    # lets virsh/virt-manager run without sudo
ADD_ADMIN_GROUPS="${WIN11_ADD_GROUPS:-1}"

# Packages: kept configurable so CachyOS/Arch variants can replace a component.
REQUIRED_PACKAGES=(qemu-desktop libvirt virt-install virt-manager virt-viewer edk2-ovmf swtpm spice spice-gtk spice-protocol spice-vdagent dnsmasq iptables acl freerdp remmina)

# Prefer explicitly configured paths, then search mounted Ventoy/data media.
# The external SSD may be mounted under either /run/media/$USER or /media/$USER;
# do not assume one exact mountpoint or one exact ISO filename.
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

SYSCTL_FILE="/etc/sysctl.d/99-${VM_NAME}-hugepages.conf"
MODE=check
INSTALL_PACKAGES=1
OPERATION_MODE=existing
FORCE=0

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '[win11-vm] %s\n' "$*"; }
usage() { cat <<'EOF'
Usage: scripts/win11-zvol-vm.sh [--check|--dry-run|--apply|--network-up|--network-down] [--no-install] [--fresh-install --force]
--check       read-only prerequisite check (default)
--dry-run     print planned mutating commands without executing them
--apply       install packages, reserve hugepages, download media, create ZVOL and define VM
--no-install  skip package installation in --apply mode
--fresh-install --force  explicitly destroy and recreate this VM and its ZVOL

Set WIN11_ISO_URL to an authorized Microsoft download URL, or provide WIN11_ISO_PATH.
EOF
}
while (($#)); do
  case "$1" in
    --check) MODE=check; shift;;
    --dry-run) MODE=dry; shift;;
    --apply) MODE=apply; shift;;
    --network-up) MODE=network-up; shift;;
    --network-down) MODE=network-down; shift;;
    --no-install) INSTALL_PACKAGES=0; shift;;
    --fresh-install) OPERATION_MODE=fresh-install; shift;;
    --force) FORCE=1; shift;;
    -h|--help) usage; exit 0;;
    *) die "unknown option: $1";;
  esac
done
# Microsoft documents that OOBE ZDP updates are mandatory once networking is
# available.  A destructive fresh install therefore starts offline unless the
# caller explicitly overrides WIN11_NETWORK_LINK_STATE=up.  The link can be
# enabled later with --network-up after the OOBE base setup is complete.
if [[ "$OPERATION_MODE" == fresh-install && -z "${WIN11_NETWORK_LINK_STATE+x}" ]]; then
  NETWORK_LINK_STATE=down
fi
[[ "$MODE" == apply ]] && DRY_RUN=0 || DRY_RUN=1
if [[ "$OPERATION_MODE" == fresh-install && "$FORCE" != 1 ]]; then
  die '--fresh-install requires --force; existing VM/ZVOL is never removed implicitly.'
fi
run() { if (( DRY_RUN )); then printf '+ '; printf '%q ' "$@"; printf '\n'; else "$@"; fi; }
as_root() { if (( EUID == 0 )); then run "$@"; else run sudo "$@"; fi; }

check_host() {
  local failed=0
  log "VM=$VM_NAME pool=$POOL zvol=$ZVOL size=$VOLSIZE RAM=${RAM_MIB}MiB vCPUs=$VCPUS"
  log "2MiB hugepages: configured=$(cat /proc/sys/vm/nr_hugepages 2>/dev/null || echo unavailable), requested=$HUGEPAGES"
  for c in zfs zpool curl; do
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
  return "$failed"
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
    if sudo -u "$VM_QEMU_USER" test -r "$source" 2>/dev/null; then
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

fresh_install_reset() {
  [[ "$OPERATION_MODE" == fresh-install ]] || return 0
  (( FORCE )) || die 'Refusing destructive VM reset without --force.'
  log "Fresh install requested: removing only the $VM_NAME definition and $ZVOL"
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
    as_root virsh -c qemu:///system undefine "$VM_NAME" --nvram >/dev/null 2>&1 || \
      as_root virsh -c qemu:///system undefine "$VM_NAME"
  fi
  if zfs list -H -o name "$ZVOL" >/dev/null 2>&1; then
    # A forensic snapshot/clone can keep the volume busy.  Fresh-install is
    # explicitly destructive, so remove dependents only in this mode; normal
    # reruns retain the VM and all snapshots.
    local dependents
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

create_zvol() {
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
  virt_args=(virt-install --connect qemu:///system --name "$VM_NAME" --uuid "$DOMAIN_UUID" --memory "$RAM_MIB" \
    --vcpus "$VCPUS,sockets=$CPU_SOCKETS,cores=$CPU_CORES,threads=$CPU_THREADS" --cpu "$CPU_MODE" "${memory_args[@]}" \
    --controller "type=scsi,model=$SCSI_MODEL" \
    --disk "path=$ZVOL_DEV,format=raw,device=disk,bus=$DISK_BUS,cache=$CACHE_MODE,io=$IO_MODE,discard=$DISCARD_MODE,detect_zeroes=$DETECT_ZEROES,serial=$DISK_SERIAL$disk_boot" \
    --disk "path=$WIN11_ISO_PATH,device=cdrom,readonly=on$iso_boot" --disk "path=$VIRTIO_ISO_PATH,device=cdrom,readonly=on" --disk "path=$SUPPORT_ISO,device=cdrom,readonly=on" \
    --network "network=default,model=$NETWORK_MODEL,mac=$MAC" --osinfo "$OS_VARIANT" --boot uefi,menu=off --tpm "default,model=$TPM_MODEL" \
    --features smm.state=on --graphics "$GRAPHICS_TYPE,streaming.mode=$SPICE_STREAMING_MODE,image.compression=$SPICE_IMAGE_COMPRESSION" \
    --check path_in_use=off,mac_in_use=off \
    --video "$VIDEO_MODEL" --noautoconsole --noreboot --dry-run --print-xml)
  if (( EUID == 0 )); then "${virt_args[@]}" > "$xml"; else sudo "${virt_args[@]}" > "$xml"; fi
  sed -i "s#</domain>#<sysinfo type='smbios'><system><entry name='manufacturer'>QEMU</entry><entry name='product'>KVM Windows 11</entry><entry name='serial'>$SMBIOS_SERIAL</entry></system></sysinfo></domain>#" "$xml"
  # Keep firmware boot deterministic: the original Windows ISO is the only
  # bootable CD; VirtIO/support media are data CDs and must never win boot.
  BOOT_FROM_ISO="$BOOT_FROM_ISO" WIN11_NETWORK_LINK_STATE="$NETWORK_LINK_STATE" python3 - "$xml" <<'PY'
import sys
import os
from xml.etree import ElementTree as ET
path = sys.argv[1]
ET.register_namespace('', 'http://libvirt.org/schemas/domain/qemu/1.0')
root = ET.parse(path).getroot()
for interface in root.findall('devices/interface'):
    link = interface.find('link')
    if link is None:
        link = ET.SubElement(interface, 'link')
    link.set('state', os.environ.get('WIN11_NETWORK_LINK_STATE', 'up'))
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
}

start_vm() {
  [[ "$START_VM" == 1 ]] || { log "VM start disabled (WIN11_START_VM=$START_VM)"; return 0; }
  local state
  state="$(as_root virsh -c qemu:///system domstate "$VM_NAME" 2>/dev/null | head -1 || true)"
  case "$state" in
    running|paused) log "VM already active: $VM_NAME ($state)" ;;
    *)
      as_root virsh -c qemu:///system start "$VM_NAME"
      if [[ "$OPERATION_MODE" == fresh-install && "$BOOT_FROM_ISO" == 1 ]]; then
        # Windows El Torito images wait for a key; feed it once so a fresh run
        # does not require a viewer or manual console interaction.
        sleep 5
        as_root virsh -c qemu:///system qemu-monitor-command "$VM_NAME" --hmp 'sendkey ret' >/dev/null 2>&1 || true
      fi
      ;;
  esac
}

set_network_link() {
  local state="$1" iface
  iface="$(as_root virsh -c qemu:///system domiflist "$VM_NAME" 2>/dev/null | awk 'NR > 2 && $1 != "" {print $1; exit}')"
  [[ -n "$iface" ]] || die "No active libvirt interface found for $VM_NAME"
  as_root virsh -c qemu:///system domif-setlink "$VM_NAME" "$iface" "$state"
  log "Guest network link set to $state ($iface)"
}

if [[ "$MODE" == check ]]; then
  check_host
  exit $?
fi
if [[ "$MODE" == network-up || "$MODE" == network-down ]]; then
  set_network_link "${MODE#network-}"
  exit 0
fi
install_packages
enable_libvirt
ensure_default_network
ensure_vm_firewall
download_media
stage_media
build_install_iso
fresh_install_reset
if [[ "$OPERATION_MODE" == fresh-install && -z "${WIN11_BOOT_FROM_ISO:-}" ]]; then
  BOOT_FROM_ISO=1
fi
reserve_hugepages
create_zvol
define_vm
start_vm
log "Done. VM state: $(as_root virsh -c qemu:///system domstate "$VM_NAME" | head -1)"

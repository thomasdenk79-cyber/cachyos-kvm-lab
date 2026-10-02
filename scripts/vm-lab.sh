#!/usr/bin/env bash
# Build a small, repeatable libvirt lab: CachyOS, Ubuntu 24.04 and Windows 11.
# Safe default: download/prepare only. Use --create to define/start guests.
set -Eeuo pipefail
ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
STATE_DIR=${VM_LAB_STATE_DIR:-$ROOT_DIR/.vm-lab}
ISO_DIR=${VM_LAB_ISO_DIR:-/var/lib/libvirt/boot}
DISK_DIR=${VM_LAB_DISK_DIR:-/var/lib/libvirt/images}
RAM_MIB=${VM_LAB_RAM_MIB:-16384}; VCPUS=${VM_LAB_VCPUS:-4}; DISK_GIB=${VM_LAB_DISK_GIB:-80}
UBUNTU_URL=${UBUNTU_URL:-https://releases.ubuntu.com/24.04/ubuntu-24.04.5.1-desktop-amd64.iso}
CACHYOS_URL=${CACHYOS_URL:-https://mirror.cachyos.org/ISO/desktop/260809/cachyos-desktop-linux-260809.iso}
WIN11_ISO=${WIN11_ISO:-$ISO_DIR/Windows11.iso}
log(){ printf '[vm-lab] %s\n' "$*"; }; die(){ printf '[vm-lab] ERROR: %s\n' "$*" >&2; exit 1; }
run_root(){ ((EUID==0)) && "$@" || sudo "$@"; }
need(){ command -v "$1" >/dev/null || die "Fehlt: $1"; }
prepare(){
  need curl; need virsh; need qemu-img
  run_root install -d -m 0755 "$ISO_DIR" "$DISK_DIR"
  mkdir -p "$STATE_DIR"; log "ISO-Verzeichnis: $ISO_DIR"
  download ubuntu "$UBUNTU_URL" "$ISO_DIR/ubuntu-24.04.iso"
  download cachyos "$CACHYOS_URL" "$ISO_DIR/cachyos.iso"
  if [[ -f "$WIN11_ISO" ]]; then log "Windows-ISO gefunden: $WIN11_ISO"; else log "Windows-ISO fehlt (gesetzt über WIN11_ISO=$WIN11_ISO)"; fi
  emit_unattend
  emit_boot_entry
}
download(){ local name=$1 url=$2 out=$3; [[ -s $out ]] && { log "$name ISO vorhanden"; return; }; log "Lade $name ISO herunter"; run_root curl -fL --retry 3 --retry-delay 5 -o "$out.part" "$url"; run_root mv "$out.part" "$out"; }
emit_unattend(){
  mkdir -p "$STATE_DIR/autounattend" "$STATE_DIR/cloud-init"
  cat > "$STATE_DIR/autounattend/ubuntu24-user-data" <<'EOF'
#cloud-config
autoinstall:
  version: 1
  identity: {hostname: ubuntu24-vm, username: lab, password: "$6$rounds=4096$CHANGE-ME$CHANGE-ME"}
  storage: {layout: {name: lvm}}
  ssh: {install-server: true, allow-pw: true}
  shutdown: reboot
EOF
  cat > "$STATE_DIR/autounattend/cachyos.md" <<'EOF'
CachyOS uses the graphical installer. The VM is created with the ISO attached;
finish the short install interactively, then remove the ISO with:
  virsh change-media cachyos-vm sda --eject --config
EOF
  cat > "$STATE_DIR/autounattend/autounattend-windows.xml" <<'EOF'
<!-- Template only: set a legal edition/product key and local account before use. -->
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
 <settings pass="windowsPE"><component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"><UserData><AcceptEula>true</AcceptEula></UserData></component></settings>
</unattend>
EOF
  log "Unattended-Vorlagen geschrieben: $STATE_DIR/autounattend"
}
emit_boot_entry(){
  mkdir -p "$STATE_DIR/boot"
  cat > "$STATE_DIR/boot/vm-lab-iommu.conf" <<'EOF'
title   CachyOS (VM lab IOMMU test)
linux   /vmlinuz-linux-cachyos
initrd  /initramfs-linux-cachyos.img
options root=ZFS=zpcachyos/ROOT/cos/root rw intel_iommu=on iommu=pt
EOF
  log "Optionaler systemd-boot Eintrag vorbereitet: $STATE_DIR/boot/vm-lab-iommu.conf"
}
define_vm(){
  local name=$1 iso=$2 disk=$3; [[ -s "$iso" ]] || die "ISO fehlt: $iso"
  run_root qemu-img create -f qcow2 "$disk" "${DISK_GIB}G" >/dev/null 2>&1 || true
  if run_root virsh dominfo "$name" >/dev/null 2>&1; then log "$name existiert bereits"; return; fi
  run_root virt-install --connect qemu:///system --name "$name" --memory "$RAM_MIB" --vcpus "$VCPUS" \
    --cpu host-model --machine q35 --disk "path=$disk,format=qcow2,bus=virtio" \
    --cdrom "$iso" --network network=default,model=virtio --graphics spice \
    --boot uefi --noautoconsole --osinfo detect=on,require=off
}
create(){
  run_root systemctl enable --now libvirtd.service 2>/dev/null || run_root systemctl enable --now virtqemud.socket virtnetworkd.socket
  run_root virsh net-start default 2>/dev/null || true; run_root virsh net-autostart default 2>/dev/null || true
  define_vm cachyos-vm "$ISO_DIR/cachyos.iso" "$DISK_DIR/cachyos-vm.qcow2"
  define_vm ubuntu24-vm "$ISO_DIR/ubuntu-24.04.iso" "$DISK_DIR/ubuntu24-vm.qcow2"
  [[ -s "$WIN11_ISO" ]] || die "Windows-ISO fehlt; WIN11_ISO=/pfad/Windows11.iso setzen"
  define_vm win11-vm "$WIN11_ISO" "$DISK_DIR/win11-vm.qcow2"
}
install_boot(){ [[ -d /boot/loader/entries ]] || die "/boot/loader/entries nicht gefunden"; run_root install -m 0644 "$STATE_DIR/boot/vm-lab-iommu.conf" /boot/loader/entries/vm-lab-iommu.conf; log "Eintrag installiert; Standard-Boot bleibt unverändert."; }
case "${1:-prepare}" in prepare) prepare;; create) prepare; create;; install-boot) install_boot;; status) run_root virsh list --all;; *) echo "Usage: $0 {prepare|create|install-boot|status}"; exit 2;; esac

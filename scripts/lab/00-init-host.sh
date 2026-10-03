#!/usr/bin/env bash
# 00-init-host.sh - einmalige Host-Vorbereitung: Dirs, Key, Credentials, DHCP-Leases.
set -euo pipefail
cd "$(dirname "$0")"; source ./env.sh

mkdir -p "$LAB_WORK" "$LAB_SEED"
sudo pacman -S --noconfirm --needed virt-install swtpm edk2-ovmf libvirt expect remmina freerdp >/dev/null

[ -f "$SSH_KEY" ] || ssh-keygen -t ed25519 -N "" -C "kvm-lab" -f "$SSH_KEY" >/dev/null
mkdir -p "$(dirname "$CREDS_FILE")"
if [ ! -f "$CREDS_FILE" ]; then
  umask 077
  printf 'LAB_VM_PASSWORD=%s\n' "$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)" > "$CREDS_FILE"
  echo "Neues VM-Passwort erzeugt in $CREDS_FILE"
fi
chmod 600 "$CREDS_FILE"

# default-Network anlegen, falls fehlend (Migrations-Ueberbleibsel)
if ! sudo virsh -c qemu:///system net-info default >/dev/null 2>&1; then
  cat > /tmp/default-net.xml <<'XML'
<network>
  <name>default</name>
  <forward mode='nat'>
    <nat><port start='1024' end='65535'/></nat>
  </forward>
  <bridge name='virbr0' stp='on' delay='0'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.100' end='192.168.122.200'/>
    </dhcp>
  </ip>
</network>
XML
  sudo virsh -c qemu:///system net-define /tmp/default-net.xml
fi
sudo virsh -c qemu:///system net-start default 2>/dev/null || true
sudo virsh -c qemu:///system net-autostart default 2>/dev/null || true

# feste IPs im default-Network
for vm in vm-ubuntu vm-cachyos vm-win11; do
  mac=$(vm_mac "$vm"); ip=$(vm_ip "$vm")
  if ! virsh net-dumpxml default | grep -q "$mac"; then
    sudo virsh -c qemu:///system net-update default add ip-dhcp-host \
      "<host mac='$mac' name='$vm' ip='$ip'/>" --live --config
  fi
done
systemctl is-active libvirtd >/dev/null || sudo systemctl enable --now libvirtd
echo "Host-Init OK"

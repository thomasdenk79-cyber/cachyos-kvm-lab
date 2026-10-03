#!/usr/bin/env bash
# 50-connect.sh - Host-Anbindung: ssh-Config, /etc/hosts, Remmina-RDP-Profile.
set -euo pipefail
cd "$(dirname "$0")"; source ./env.sh
PW=$(get_pass)

# SSH-Config
touch ~/.ssh/config; chmod 600 ~/.ssh/config
if ! grep -q "BEGIN kvm-lab" ~/.ssh/config; then
cat >> ~/.ssh/config <<EOF
# BEGIN kvm-lab
Host vm-ubuntu vm-cachyos
  User $VM_USER
  IdentityFile $SSH_KEY
  IdentitiesOnly yes
Host vm-win11
  User $VM_USER
  IdentityFile $SSH_KEY
  IdentitiesOnly yes
  PreferredAuthentications publickey,password
# END kvm-lab
EOF
fi

# /etc/hosts
if ! grep -q "vm-ubuntu" /etc/hosts; then
  printf '%s\n' "192.168.122.51 vm-ubuntu" "192.168.122.52 vm-cachyos" "192.168.122.53 vm-win11" | sudo tee -a /etc/hosts >/dev/null
fi

# Remmina-Profile (RDP = Protokoll-ID 4)
mkdir -p ~/.local/share/remmina
for vm in vm-ubuntu vm-cachyos vm-win11; do
  ip=$(vm_ip $vm)
  cat > ~/.local/share/remmina/$vm.remmina <<RDP
[remmina]
version=1
name=$vm
protocol=4
server=$ip
port=3389
username=$VM_USER
password=$PW
colordepth=16
resolution-width=1600
resolution-height=1000
enable-autostart-mode=yes
RDP
  chmod 600 ~/.local/share/remmina/$vm.remmina
done
# Fallback-Freerdp-Desktopstarter (falls Remmina-Zahlen anders sind)
mkdir -p ~/Bilder/../.local/share/applications 2>/dev/null || true
for vm in vm-ubuntu vm-cachyos vm-win11; do
  ip=$(vm_ip $vm)
  cat > ~/.local/share/applications/kvmlab-$vm.desktop <<DESK
[Desktop Entry]
Type=Application
Name=RDP $vm
Exec=xfreerdp /v:$ip /u:$VM_USER /p:$PW /dynamic-resolution /cert:ignore
Categories=Network;RemoteAccess;
DESK
  chmod 600 ~/.local/share/applications/kvmlab-$vm.desktop
done
echo "Connect-Setup OK (Passwort in ~/.local/share/remmina/*.remmina, chmod 600)"

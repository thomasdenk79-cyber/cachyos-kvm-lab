#!/usr/bin/env bash
# Gemeinsame Variablen des VM-Labs. Alle lab-Skripte quellen diese Datei.
set -euo pipefail

LAB_DIR="/srv/vms"
LAB_DISKS="$LAB_DIR/disks"
LAB_ISO="$LAB_DIR/iso"
LAB_SEED="$LAB_DIR/seed"
LAB_WORK="$LAB_DIR/work"
LAB_ISO_WIN="$LAB_ISO/Windows11_Client_x64_de-de_26300_9457.iso"
LAB_ISO_UBUNTU="$LAB_ISO/ubuntu-24.04.4-desktop-amd64.iso"
LAB_ISO_CACHY="$LAB_ISO/cachyos-desktop-linux-260809.iso"
LAB_ISO_VIRTIO="$LAB_ISO/virtio-win.iso"
CREDS_FILE="$HOME/.config/kvm-lab/creds.env"
SSH_KEY="$HOME/.ssh/kvm_lab_ed25519"

VM_USER="vmadmin"
VM_MEM_MIB=12288
VM_VCPUS=4
VM_DISK_GB=200

vm_mac() { case "$1" in vm-ubuntu) echo 52:54:00:11:00:51;; vm-cachyos) echo 52:54:00:11:00:52;; vm-win11) echo 52:54:00:11:00:53;; *) return 1;; esac; }
vm_ip()  { case "$1" in vm-ubuntu) echo 192.168.122.51;; vm-cachyos) echo 192.168.122.52;; vm-win11) echo 192.168.122.53;; *) return 1;; esac; }

get_pass() { grep '^LAB_VM_PASSWORD=' "$CREDS_FILE" | cut -d= -f2-; }
hash_pass() { openssl passwd -6 "$(get_pass)"; }
pubkey() { cat "$SSH_KEY.pub"; }

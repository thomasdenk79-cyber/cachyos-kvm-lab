#!/usr/bin/env bash
# 25-advance.sh <vm> - haelt die Domain nach ISO-Ende am Laufen: wenn shut off und
# Install-XML noch aktiv, finale XML (ohne ISOs) definieren und starten. Idempotent.
set -euo pipefail
cd "$(dirname "$0")"; source ./env.sh
VM=${1:?}
state=$(sudo virsh -c qemu:///system domstate "$VM" 2>/dev/null || echo missing)
[ "$state" = "shut off" ] || exit 0
cur=$(sudo virsh -c qemu:///system dumpxml "$VM" | grep -c "device='cdrom'\|device=\"cdrom\"" || true)
final="/tmp/$VM-final.xml"
[ -f "$final" ] || final="$LAB_WORK/$VM-final.xml"
if [ "$cur" -gt 0 ] && [ -f "$final" ]; then
  echo "$VM shut off nach ISO-Phase -> finale Definition"
  sudo virsh -c qemu:///system destroy "$VM" 2>/dev/null || true
  sudo virsh -c qemu:///system define "$final"
  sudo virsh -c qemu:///system start "$VM"
fi

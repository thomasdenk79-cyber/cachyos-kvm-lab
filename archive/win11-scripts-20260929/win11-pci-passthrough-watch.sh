#!/usr/bin/env bash
set -Eeuo pipefail

VM_NAME="${1:?VM name required}"
BDF="${2:?PCI BDF required}"
IFACE="${3:?host interface required}"
CONNECTION="${4:-}"
NODE="pci_${BDF//:/_}"
NODE="${NODE//./_}"

restore() {
  virsh -c qemu:///system nodedev-reattach "$NODE" >/dev/null 2>&1 \
    || sudo -n virsh -c qemu:///system nodedev-reattach "$NODE" >/dev/null 2>&1 \
    || true
  nmcli device set "$IFACE" managed yes >/dev/null 2>&1 || true
  if [[ -n "$CONNECTION" && "$CONNECTION" != "--" ]]; then
    nmcli connection up "$CONNECTION" >/dev/null 2>&1 || true
  else
    nmcli device connect "$IFACE" >/dev/null 2>&1 || true
  fi
}
trap restore EXIT INT TERM

while :; do
  state="$(virsh -c qemu:///system domstate "$VM_NAME" 2>/dev/null | head -1 || true)"
  [[ "$state" == "shut off" || -z "$state" ]] && exit 0
  sleep 2
done

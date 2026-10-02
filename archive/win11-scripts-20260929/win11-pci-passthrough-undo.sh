#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_MAC="${WIN11_PCI_HOSTDEV_MAC:-}"
BDF="${1:-}"
IFACE="${2:-}"
CONNECTION="${3:-}"
if [[ -z "$BDF" && -n "$TARGET_MAC" ]]; then
  while IFS= read -r candidate; do
    [[ -e "/sys/class/net/$candidate/device" ]] || continue
    [[ "$(cat "/sys/class/net/$candidate/address" 2>/dev/null || true)" == "$TARGET_MAC" ]] || continue
    IFACE="$candidate"
    BDF="$(basename "$(readlink -f "/sys/class/net/$candidate/device")")"
    break
  done < <(find /sys/class/net -mindepth 1 -maxdepth 1 -printf '%f\n')
fi
BDF="${BDF:-0000:00:1f.6}"
IFACE="${IFACE:-enp0s31f6}"
NODE="pci_${BDF//:/_}"
NODE="${NODE//./_}"

virsh -c qemu:///system nodedev-reattach "$NODE" >/dev/null 2>&1 \
  || sudo -n virsh -c qemu:///system nodedev-reattach "$NODE" >/dev/null 2>&1 \
  || true
nmcli device set "$IFACE" managed yes
if [[ -n "$CONNECTION" && "$CONNECTION" != "--" ]]; then
  nmcli connection up "$CONNECTION"
else
  nmcli device connect "$IFACE"
fi
printf 'Host Ethernet restored: %s (%s)\n' "$IFACE" "$BDF"

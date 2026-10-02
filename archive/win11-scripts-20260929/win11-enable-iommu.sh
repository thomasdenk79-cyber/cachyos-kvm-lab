#!/usr/bin/env bash
set -Eeuo pipefail

# Enable host prerequisites for a physical PCI NIC passed to a VM. Idempotent
# and vendor-aware. Changes boot/initramfs configuration; reboot is required.
if (( EUID != 0 )); then exec sudo "$0" "$@"; fi

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CMDLINE_FILE=/etc/kernel/cmdline
MODULE_FILE=/etc/mkinitcpio.conf.d/20-win11-vfio.conf
vendor="$(lscpu 2>/dev/null | awk -F: '/Vendor ID/ {gsub(/[[:space:]]/,"",$2); print $2; exit}')"
case "$vendor" in
  GenuineIntel) iommu=(intel_iommu=on iommu=pt) ;;
  AuthenticAMD) iommu=(amd_iommu=on iommu=pt) ;;
  *) echo 'Unbekannter CPU-Hersteller; Intel oder AMD erforderlich.' >&2; exit 1 ;;
esac

touch "$CMDLINE_FILE"
cmdline="$(cat "$CMDLINE_FILE")"
for arg in "${iommu[@]}"; do
  [[ " $cmdline " == *" $arg "*" ]] || cmdline+=" $arg"
done
printf '%s\n' "$cmdline" | xargs > "$CMDLINE_FILE"

cat > "$MODULE_FILE" <<'EOF'
# Win11 PCI passthrough: load VFIO before the host NIC driver claims the device.
MODULES+=(vfio_pci vfio_iommu_type1 vfio)
EOF

mkinitcpio -P

# CachyOS images use BLS entries. Keep Linux entries aligned with cmdline;
# leave the separate ZFSBootMenu entry untouched.
shopt -s nullglob
for entry in /boot/loader/entries/*.conf; do
  [[ "$(basename "$entry")" == zfsbootmenu.conf ]] && continue
  sed -i -E "s/^options .*/options $(cat "$CMDLINE_FILE")/" "$entry"
done

echo "IOMMU/VFIO vorbereitet: ${iommu[*]}"
echo 'Initramfs und systemd-boot-Einträge aktualisiert. Jetzt neu starten; erst danach PCI-Passthrough-VM starten.'
echo 'Prüfung nach Neustart: test -d /sys/kernel/iommu_groups/ && lsmod | grep -E "^vfio"'
echo "Undo für die Netzwerkkarte bleibt: $ROOT_DIR/scripts/win11-pci-passthrough-undo.sh"

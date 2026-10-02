#!/usr/bin/env bash
set -Eeuo pipefail

# Second VM profile: physical HP ZBook identity and Ethernet PCI passthrough.
# The shared setup script performs the destructive gate, ZVOL creation,
# OVMF-key enrollment, TPM setup, verification and lifecycle watcher.
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export VM_NAME="${VM_NAME:-win11-hpzbook}"
export WIN11_DOMAIN_UUID="${WIN11_DOMAIN_UUID:-04a08bd2-db75-4e5c-9805-616656d75c0e}"
export WIN11_SMBIOS_SERIAL="${WIN11_SMBIOS_SERIAL:-CND11338NL}"
export WIN11_DISK_SERIAL="${WIN11_DISK_SERIAL:-CND11338NL-DISK}"
export WIN11_MAC="${WIN11_MAC:-7c:4d:8f:2b:a8:ee}"
export WIN11_ZVOL="${WIN11_ZVOL:-zpcachyos/vms/win11-hpzbook}"
export WIN11_SUPPORT_ISO="${WIN11_SUPPORT_ISO:-/var/lib/libvirt/boot/win11-hpzbook-support.iso}"
export WIN11_RAM_MIB="${WIN11_RAM_MIB:-16384}"
export WIN11_VCPUS="${WIN11_VCPUS:-4}"
export WIN11_CPU_CORES="${WIN11_CPU_CORES:-4}"
export WIN11_COMPRESSION="${WIN11_COMPRESSION:-zstd-1}"
export WIN11_CACHE_MODE="${WIN11_CACHE_MODE:-none}"
export WIN11_IO_MODE="${WIN11_IO_MODE:-io_uring}"
export WIN11_DISCARD_MODE="${WIN11_DISCARD_MODE:-unmap}"
export WIN11_NETWORK_MODEL="${WIN11_NETWORK_MODEL:-e1000e}"
export WIN11_PCI_HOSTDEV_BDF="${WIN11_PCI_HOSTDEV_BDF:-}"
export WIN11_PCI_HOSTDEV_IFACE="${WIN11_PCI_HOSTDEV_IFACE:-}"
export WIN11_PCI_HOSTDEV_AUTO="${WIN11_PCI_HOSTDEV_AUTO:-1}"
export WIN11_PCI_HOSTDEV_MAC="${WIN11_PCI_HOSTDEV_MAC:-7c:4d:8f:2b:a8:ee}"
export WIN11_PCI_HOSTDEV_FALLBACK_IFACE="${WIN11_PCI_HOSTDEV_FALLBACK_IFACE:-}"
export WIN11_PCI_WATCHER="${WIN11_PCI_WATCHER:-1}"

exec "$ROOT_DIR/scripts/win11-zvol-vm.sh" "$@"

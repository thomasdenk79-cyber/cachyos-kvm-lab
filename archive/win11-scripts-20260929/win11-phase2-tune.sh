#!/usr/bin/env bash
set -Eeuo pipefail

# Apply only after Windows has VirtIO storage/network drivers installed and
# the guest has completed several clean boots. This changes its virtual
# hardware, so it requires an explicit stability acknowledgement.
VM_NAME="${1:-${VM_NAME:-win11-siemens}}"
MODE="${2:---check}"
[[ "$MODE" == --check || "$MODE" == --apply ]] || { echo "Usage: $0 VM_NAME [--check|--apply]" >&2; exit 2; }
if [[ "$MODE" == --apply && "${WIN11_PHASE2_STABLE_BOOT_CONFIRM:-}" != YES ]]; then
  echo 'Set WIN11_PHASE2_STABLE_BOOT_CONFIRM=YES after verifying multiple stable Windows boots.' >&2
  exit 2
fi
run_virsh() { if (( EUID == 0 )); then virsh -c qemu:///system "$@"; else sudo virsh -c qemu:///system "$@"; fi; }
state="$(run_virsh domstate "$VM_NAME" 2>/dev/null | head -1 || true)"
[[ -n "$state" ]] || { echo "Unknown VM: $VM_NAME" >&2; exit 1; }
[[ "$state" == 'shut off' ]] || { echo "Stop the VM first (current state: $state)." >&2; exit 1; }
xml="$(run_virsh dumpxml "$VM_NAME" --inactive)"
if grep -q "<hostdev mode='subsystem' type='pci'" <<< "$xml"; then
  passthrough=1
else
  passthrough=0
fi
if [[ "$MODE" == --check ]]; then
  echo "VM=$VM_NAME state=$state pci-passthrough=$passthrough"
  echo 'Planned: SATA -> VirtIO-SCSI; remove installer CD-ROMs; boot from system disk; add QEMU Guest Agent channel.'
  (( passthrough )) || echo 'Planned: e1000e -> virtio-net with vhost.'
  echo 'Requires VirtIO storage/network drivers installed in Windows before --apply.'
  exit 0
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
run_virsh dumpxml "$VM_NAME" --inactive > "$tmp"
python3 - "$tmp" "$passthrough" <<'PY'
import sys
from xml.etree import ElementTree as ET
p, passthrough = sys.argv[1], sys.argv[2] == '1'
tree = ET.parse(p); root = tree.getroot(); devices = root.find('devices')
disk = next((d for d in devices.findall('disk') if d.get('device') == 'disk'), None)
if disk is None: raise SystemExit('No system disk found')
target = disk.find('target'); driver = disk.find('driver')
if target is None or driver is None: raise SystemExit('System disk XML incomplete')
target.set('bus', 'scsi')
target.set('dev', 'sda')
for boot in list(disk.findall('boot')): disk.remove(boot)
ET.SubElement(disk, 'boot', {'order':'1'})
for address in list(disk.findall('address')): disk.remove(address)
driver.set('name', 'qemu')
for cd in list(devices.findall('disk')):
    if cd.get('device') == 'cdrom': devices.remove(cd)
if not passthrough:
    for interface in devices.findall('interface'):
        model = interface.find('model')
        if model is not None: model.set('type', 'virtio')
        driver = interface.find('driver')
        if driver is None: driver = ET.SubElement(interface, 'driver')
        driver.set('name', 'vhost')
channel_exists = any((c.find('target') is not None and c.find('target').get('name') == 'org.qemu.guest_agent.0') for c in devices.findall('channel'))
if not channel_exists:
    channel = ET.SubElement(devices, 'channel', {'type':'unix'})
    ET.SubElement(channel, 'source', {'mode':'bind'})
    ET.SubElement(channel, 'target', {'type':'virtio', 'name':'org.qemu.guest_agent.0'})
    ET.SubElement(channel, 'address', {'type':'virtio-serial', 'controller':'0', 'bus':'0', 'port':'1'})
tree.write(p, encoding='unicode')
PY
run_virsh define "$tmp"
echo "Phase 2 hardware tuning applied to $VM_NAME. Start Windows and verify boot, storage, network, and guest-agent before further cleanup."

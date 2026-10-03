#!/usr/bin/env bash
# 26-win-eject-watcher.sh - wirft beim ersten Guest-Reboot alle CDs aus vm-win11,
# damit Windows-Setup nicht erneut vom ISO bootet (strict bootindex=1 auf CD).
set -euo pipefail
cd "$(dirname "$0")"; source ./env.sh
echo "warte auf reboot-event von vm-win11..."
sudo virsh -c qemu:///system event vm-win11 reboot --timeout 7200
echo "Reboot erkannt -> CDs werden ausgeworfen"
sleep 3
for tgt in sdb sdc sdd; do
  sudo virsh -c qemu:///system update-device vm-win11 --eject --target "$tgt" 2>/dev/null || true
done
sudo virsh -c qemu:///system dumpxml vm-win11 | grep -c 'device="cdrom"\|device=.cdrom.' || true
echo "EJECT_DONE"

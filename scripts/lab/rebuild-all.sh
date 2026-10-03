#!/usr/bin/env bash
# rebuild-all.sh - KALTPFAD nach Host-Neustart/VM-Verlust: baut das 3er-VM-Lab
# komplett neu auf (Idempotent; bestehende laufende Domains werden respektiert).
# Aufruf: ./rebuild-all.sh [--fresh]   --fresh = erst alle vm-* destroyen/undefinieren
set -uo pipefail
cd "$(dirname "$0")"; source ./env.sh
LOG="$LAB_WORK/rebuild.log"; mkdir -p "$LAB_WORK"; exec > >(tee -a "$LOG") 2>&1
echo "===== REBUILD $(date) ====="

if [ "${1:-}" = "--fresh" ]; then
  for vm in vm-ubuntu vm-cachyos vm-win11; do
    sudo virsh -c qemu:///system destroy "$vm" 2>/dev/null || true
    sudo virsh -c qemu:///system undefine "$vm" --nvram 2>/dev/null || true
  done
  # Achtung: bewusst KEIN --remove-all-storage (wuerde ISOs loeschen)
  rm -f "$LAB_DISKS"/*.qcow2
fi

./00-init-host.sh
./13-extract-boot.sh
./10-seed-ubuntu.sh
./11-seed-win11.sh
./12-seed-cachyos.sh

for vm in vm-ubuntu vm-win11 vm-cachyos; do
  if ! sudo virsh -c qemu:///system dominfo "$vm" >/dev/null 2>&1; then
    ./20-create-vm.sh "$vm"
  fi
done

# Eject-Watcher fuer Win11 (nur wenn noch keiner laeuft)
pgrep -f "26-win-eject[-]watcher.sh" >/dev/null || {
  setsid nohup ./26-win-eject-watcher.sh > "$LAB_WORK/eject-watcher.log" 2>&1 </dev/null &
}

# CachyOS-Live-Treiber im Hintergrund (wartet selbst auf die Konsole)
pgrep -f "31-drive-cachy[os]" >/dev/null || {
  setsid nohup ./31-drive-cachyos.exp vm-cachyos > "$LAB_WORK/drive-cachyos.log" 2>&1 </dev/null &
}

# Abschluss-Tasks
( ./40-post.sh vm-ubuntu 90;  ./25-advance.sh vm-ubuntu;  ./40-post.sh vm-ubuntu 30 ) &
( sleep 60; ./40-post.sh vm-win11 180; ./25-advance.sh vm-win11 ) &
( sleep 240; ./40-post.sh vm-cachyos 120; ./25-advance.sh vm-cachyos; ./40-post.sh vm-cachyos 30 ) &
wait
./50-connect.sh
echo "===== REBUILD FERTIG $(date) ====="

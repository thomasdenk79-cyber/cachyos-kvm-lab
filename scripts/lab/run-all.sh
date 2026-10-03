#!/usr/bin/env bash
# run-all.sh - komplette VM-Lab-Erzeugung (idempotent, seriell mit 2 parallelen Traessen).
set -uo pipefail
cd "$(dirname "$0")"; source ./env.sh
LOG=$LAB_WORK/run-all.log; mkdir -p "$LAB_WORK"; exec > >(tee -a "$LOG") 2>&1
echo "=== RUN $(date) ==="

./00-init-host.sh
./10-seed-ubuntu.sh
./11-seed-win11.sh
./12-seed-cachyos.sh

exists() { sudo virsh -c qemu:///system dominfo "$1" >/dev/null 2>&1; }

exists vm-ubuntu  || ./20-create-vm.sh vm-ubuntu
exists vm-win11   || ./20-create-vm.sh vm-win11

./40-post.sh vm-ubuntu 60 &
P1=$!
chmod +x 31-drive-cachyos.exp
until [ -b /dev/null ] && sudo virsh -c qemu:///system domstate vm-win11 >/dev/null; do sleep 5; done
./40-post.sh vm-win11 120 &
P2=$!
wait $P1; R1=$?
exists vm-cachyos || ./20-create-vm.sh vm-cachyos
./31-drive-cachyos.exp vm-cachyos
./40-post.sh vm-cachyos 90; R3=$?
wait $P2; R2=$?

./50-connect.sh
echo "=== ERGEBNIS ubuntu=$R1 win=$R2 cachyos=$R3 $(date) ==="

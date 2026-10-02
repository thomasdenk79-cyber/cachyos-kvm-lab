#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
script="$root/scripts/cachyos-venus-direct-qemu.sh"
test -x "$script"
bash -n "$script"
grep -q 'honor-guest-pat=on' "$script"
grep -q 'overlay.qcow2' "$script"
grep -q 'VK_DRIVER_FILES' "$script"
grep -q 'CACHYOS_VENUS_HOST_ICD' "$script"
grep -q 'CACHYOS_VENUS_ENABLE' "$script"
grep -q 'CACHYOS_VENUS_RENDER_NODE' "$script"
grep -q 'CACHYOS_VENUS_SPICE_GL' "$script"
grep -q 'CACHYOS_VENUS_DUAL_DISPLAY' "$script"
grep -q 'egl-headless,gl=on' "$script"
grep -q 'virtio-keyboard-pci' "$script"
grep -q 'spicevmc,id=vdagent' "$script"
printf 'PASS: direct NVIDIA Venus QEMU runner static checks\n'

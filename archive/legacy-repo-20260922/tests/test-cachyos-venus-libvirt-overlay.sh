#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
script="$root/scripts/cachyos-venus-libvirt-overlay.sh"
test -x "$script"
bash -n "$script"
grep -q 'qemu-img create' "$script"
grep -q 'virsh define' "$script"
grep -q 'CACHYOS_VENUS_RENDER_NODE' "$script"
printf 'PASS: libvirt Venus overlay clone static checks\n'

#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
script="$root/scripts/windows11-kvm-performance.sh"
test -x "$script"
bash -n "$script"
grep -q 'host-passthrough' "$script"
grep -q 'virtio-vga' "$script"
grep -q 'memorybacking' "$script"
grep -q 'bus=virtio' "$script"
printf 'PASS: Windows KVM performance script static checks\n'

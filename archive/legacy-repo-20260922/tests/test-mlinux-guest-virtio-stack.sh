#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/mlinux-guest-virtio-stack.sh"
test -x "$script"
bash -n "$script"
"$script" --help >/dev/null
grep -q 'virtio_gpu_dri.so' "$script"
grep -q 'qemu-guest-agent' "$script"
grep -q 'spice-vdagent' "$script"
grep -q 'llvmpipe' "$script"
printf 'PASS: mLinux guest VirtIO stack static checks\n'

#!/usr/bin/env bash
set -Eeuo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/mlinux-kvm-performance.sh"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test -x "$script"
bash -n "$script"
"$script" --help >/dev/null
grep -q 'accel3d' "$script"
grep -q 'rendernode' "$script"
grep -q 'streaming' "$script"
grep -q 'port=5901' "$script"
grep -q 'virtio-vga-gl' "$script"
grep -q 'max_hostmem' "$script"
grep -q 'hostmem' "$script"
grep -q 'VCPU_SOCKETS' "$script"
grep -q 'virtio-tablet-pci,bus=pcie.0,addr=0x7' "$script"
grep -q 'virtio-keyboard-pci,bus=pcie.0,addr=0x8' "$script"
grep -q 'virtio_gpu_dri.so' "$root/scripts/mlinux-guest-virtio-stack.sh"
printf 'PASS: mLinux KVM performance static checks\n'

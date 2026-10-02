#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/mlinux-kvm-virgl-benchmark.sh"
test -x "$script"
bash -n "$script"
"$script" --help >/dev/null
grep -q 'host_cpu_pct' "$script"
grep -q 'guest_cpu_pct' "$script"
grep -q 'intel_render3d_pct' "$script"
grep -q 'nvidia_gpu_pct' "$script"
grep -q 'Puppet' "$script"
printf 'PASS: mLinux KVM VirGL monitoring benchmark static checks\n'

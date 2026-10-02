#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
dir="$root/tests/windows11-gpu"
test -r "$dir/README.md"
test -r "$dir/RESULTS-20260921.md"
test -x "$dir/run-gpu-matrix.sh"
bash -n "$dir/run-gpu-matrix.sh"
for profile in baseline-intel-virtio-vga virtio-vga-gl-intel nvidia-spice-virtio-vga qxl-spice; do
  test -r "$dir/profiles/$profile.env"
done
grep -q 'EGL_NOT_INITIALIZED' "$dir/RESULTS-20260921.md"
grep -q 'no surface' "$dir/RESULTS-20260921.md"
printf 'PASS: Windows 11 GPU matrix static checks\n'

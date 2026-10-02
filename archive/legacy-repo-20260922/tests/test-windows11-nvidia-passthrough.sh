#!/usr/bin/env bash
set -Eeuo pipefail
script="$(dirname "$0")/../scripts/windows11-nvidia-passthrough.sh"
bash -n "$script"
grep -q "managed='yes'" "$script"
grep -q -- '--rollback' "$script"
printf 'PASS: NVIDIA passthrough script static checks\n'

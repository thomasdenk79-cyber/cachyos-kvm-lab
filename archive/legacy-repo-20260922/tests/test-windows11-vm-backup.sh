#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
script="$root/scripts/windows11-vm-backup.sh"
test -x "$script"
bash -n "$script"
grep -q 'OVMF_VARS' "$script"
grep -q 'SHA256SUMS' "$script"
grep -q 'tar.*--xz' "$script"
grep -q 'tar -tJf' "$script"
printf 'PASS: Windows VM backup script static checks\n'

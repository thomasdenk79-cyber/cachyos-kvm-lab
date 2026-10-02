#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
script="$root/scripts/windows11-intune-prep.sh"
test -x "$script"
bash -n "$script"
grep -q -- '--backup' "$script"
grep -q '<smbios mode=' "$script"
grep -q 'OVMF_VARS' "$script"
printf 'PASS: Windows Intune prep static checks\n'

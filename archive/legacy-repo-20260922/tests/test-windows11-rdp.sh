#!/usr/bin/env bash
set -Eeuo pipefail
script="$(dirname "$0")/../scripts/windows11-rdp.sh"
test -x "$script"
bash -n "$script"
grep -q '/sound:sys:pulse' "$script"
grep -q 'dynamic-resolution' "$script"
grep -q '/smartcard' "$script"
grep -q '/drive:fast-storage' "$script"
grep -q 'AVC444' "$script"
grep -q -- '-wallpaper' "$script"
printf 'PASS: Windows RDP profile static checks\n'

#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
script="$root/scripts/libvirt-venus-host-config.sh"
test -x "$script"
bash -n "$script"
grep -q 'seccomp_sandbox' "$script"
grep -q 'virtqemud' "$script"
grep -q -- '--restore' "$script"
printf 'PASS: libvirt Venus host sandbox automation static checks\n'

#!/usr/bin/env bash
set -Eeuo pipefail
script="$(dirname "$0")/../scripts/windows11-moonlight.sh"
test -x "$script"
bash -n "$script"
grep -q -- '--absolute-mouse' "$script"
grep -q -- '--frame-pacing' "$script"
echo 'PASS: Moonlight launcher static checks'

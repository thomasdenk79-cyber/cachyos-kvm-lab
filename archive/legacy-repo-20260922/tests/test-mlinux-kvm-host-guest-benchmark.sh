#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
script="$root/scripts/mlinux-kvm-host-guest-benchmark.sh"
test -x "$script"
bash -n "$script"
grep -q 'host-glmark2' "$script"
grep -q 'guest-glmark2' "$script"
grep -q 'host-sysbench' "$script"
grep -q 'guest-sysbench' "$script"
printf 'PASS: host/guest benchmark static checks\n'

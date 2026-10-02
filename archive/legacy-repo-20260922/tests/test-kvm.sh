#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
bash -n "$root/scripts/kvm-check.sh"
"$root/scripts/kvm-check.sh" --help >/dev/null
echo "kvm tests passed"

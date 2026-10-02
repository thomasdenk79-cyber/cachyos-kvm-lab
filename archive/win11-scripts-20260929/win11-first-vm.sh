#!/usr/bin/env bash
set -Eeuo pipefail

# First Windows 11 VM profile. It deliberately uses libvirt's default NAT
# network and a virtual e1000e NIC. PCI passthrough is hard-disabled so a
# copied shell environment cannot attach a physical host device by accident.
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/win11-first-vm.profile"

# Optional local override file. Keep machine-specific experiments outside Git,
# for example: WIN11_FIRST_ENV_FILE=$HOME/.config/workstation-setup/win11.env
FIRST_ENV_FILE="${WIN11_FIRST_ENV_FILE:-}"
if [[ -n "$FIRST_ENV_FILE" ]]; then
  [[ -r "$FIRST_ENV_FILE" ]] || { printf 'ERROR: First-VM override is not readable: %s\n' "$FIRST_ENV_FILE" >&2; exit 1; }
  # The file is intentionally shell syntax so values can be quoted safely.
  # It should contain only WIN11_* assignments, no commands.
  # shellcheck source=/dev/null
  source "$FIRST_ENV_FILE"
fi

exec "$ROOT_DIR/scripts/win11-zvol-vm.sh" "$@"

#!/usr/bin/env bash
set -Eeuo pipefail

# Configure the host-wide libvirt setting required by QEMU Venus.
# This deliberately affects every QEMU guest; use --restore with a saved file.

MODE="${1:---check}"
CONF=/etc/libvirt/qemu.conf

case "$MODE" in
  --check)
    grep -Eq '^seccomp_sandbox[[:space:]]*=[[:space:]]*0$' "$CONF"
    printf 'seccomp_sandbox=0\n'
    ;;
  --apply)
    [[ $EUID -eq 0 ]] || { printf 'run with sudo\n' >&2; exit 1; }
    backup="$CONF.venus-$(date +%Y%m%d-%H%M%S).bak"
    install -m 0600 "$CONF" "$backup"
    if grep -Eq '^seccomp_sandbox[[:space:]]*=' "$CONF"; then
      sed -Ei 's/^seccomp_sandbox[[:space:]]*=.*/seccomp_sandbox = 0/' "$CONF"
    else
      printf '\nseccomp_sandbox = 0\n' >> "$CONF"
    fi
    systemctl restart virtqemud
    printf 'backup=%s\n' "$backup"
    ;;
  --restore)
    [[ $EUID -eq 0 ]] || { printf 'run with sudo\n' >&2; exit 1; }
    backup="${2:-}"
    [[ -r "$backup" ]] || { printf 'usage: %s --restore /path/to/qemu.conf.bak\n' "$0" >&2; exit 1; }
    install -m 0600 "$backup" "$CONF"
    systemctl restart virtqemud
    ;;
  *)
    printf 'usage: %s --check|--apply|--restore BACKUP\n' "$0" >&2
    exit 2
    ;;
esac

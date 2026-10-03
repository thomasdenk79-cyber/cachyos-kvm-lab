#!/usr/bin/env bash
# 12-seed-cachyos.sh - Seed-CD fuer den CachyOS-Live-Lauf (Installer + Credentials).
set -euo pipefail
cd "$(dirname "$0")"; source ./env.sh
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cp "$(dirname "$0")/files/cachyos-live.sh" "$TMP/"
get_pass > "$TMP/vm.pass"
chmod 600 "$TMP/vm.pass" 2>/dev/null || true
pubkey > "$TMP/authorized_keys.pub"
rm -f "$LAB_SEED/lab-cachyos.iso"
xorriso -as mkisofs -o "$LAB_SEED/lab-cachyos.iso" -volid LABSEED -r "$TMP" >/dev/null
ls -l "$LAB_SEED/lab-cachyos.iso"

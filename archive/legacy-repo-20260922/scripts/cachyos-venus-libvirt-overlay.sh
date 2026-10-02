#!/usr/bin/env bash
set -Eeuo pipefail

# Define a disposable libvirt clone backed by a qcow2 overlay.
BASE_DOMAIN="${CACHYOS_VENUS_BASE_DOMAIN:-cachyos-venus-test}"
CLONE_DOMAIN="${CACHYOS_VENUS_CLONE_DOMAIN:-cachyos-venus-nvidia-manual}"
BASE_IMAGE="${CACHYOS_VENUS_IMAGE:-/var/lib/libvirt/images/cachyos-venus-test.qcow2}"
OVERLAY="${CACHYOS_VENUS_CLONE_IMAGE:-/var/lib/libvirt/images/cachyos-venus-nvidia-manual.qcow2}"
NVRAM="/var/lib/libvirt/qemu/nvram/${CLONE_DOMAIN}_VARS.fd"
RENDER_NODE="${CACHYOS_VENUS_RENDER_NODE:-/dev/dri/renderD128}"
MODE="${1:---check}"

[[ $EUID -eq 0 ]] || { printf 'run with sudo\n' >&2; exit 1; }
virsh dominfo "$BASE_DOMAIN" >/dev/null

case "$MODE" in
  --check)
    [[ "$(virsh domstate "$BASE_DOMAIN")" == 'shut off' ]]
    printf 'libvirt overlay prerequisites OK\n'
    ;;
  --define)
    [[ "$(virsh domstate "$BASE_DOMAIN")" == 'shut off' ]] || { printf 'base domain must be shut off\n' >&2; exit 1; }
    if ! virsh dominfo "$CLONE_DOMAIN" >/dev/null 2>&1; then
      [[ -e "$OVERLAY" ]] || qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMAGE" "$OVERLAY"
      chown libvirt-qemu:kvm "$OVERLAY"
      [[ -e "$NVRAM" ]] || cp "/var/lib/libvirt/qemu/nvram/${BASE_DOMAIN}_VARS.fd" "$NVRAM"
      chown libvirt-qemu:kvm "$NVRAM"
      xml="$(mktemp)"
      trap 'rm -f "$xml"' EXIT
      virsh dumpxml "$BASE_DOMAIN" > "$xml"
      uuid="$(uuidgen)"
      sed -i \
        -e "s#<name>${BASE_DOMAIN}</name>#<name>${CLONE_DOMAIN}</name>#" \
        -e "s#<uuid>[^<]*</uuid>#<uuid>${uuid}</uuid>#" \
        -e "s#${BASE_DOMAIN}_VARS.fd#${CLONE_DOMAIN}_VARS.fd#" \
        -e "0,#<source file='[^']*'/>#s#<source file='[^']*'/>#<source file='${OVERLAY}'/>#" \
        -e "0,#<mac address='[^']*'/>#s#<mac address='[^']*'/>#<mac address='52:54:00:00:92:6d'/>#" \
        -e "s#rendernode='/dev/dri/renderD[0-9]*'#rendernode='${RENDER_NODE}'#" "$xml"
      virsh define "$xml"
    else
      printf 'domain already defined: %s\n' "$CLONE_DOMAIN"
    fi
    ;;
  --start)
    virsh start "$CLONE_DOMAIN"
    ;;
  --stop)
    virsh shutdown "$CLONE_DOMAIN" || true
    ;;
  *)
    printf 'usage: %s --check|--define|--start|--stop\n' "$0" >&2
    exit 2
    ;;
esac

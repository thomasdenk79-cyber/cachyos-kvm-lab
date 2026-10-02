#!/usr/bin/env bash
set -Eeuo pipefail

# Apply reversible, Windows-safe KVM tuning without replacing the VirtIO-DOD GPU.
VM_NAME="${WIN11_KVM_VM_NAME:-windows11-generic-test}"
MODE="${1:---check}"

[[ $EUID -eq 0 ]] || { printf 'run with sudo\n' >&2; exit 1; }
xml() { virsh dumpxml --inactive "$VM_NAME"; }
check() {
  local x
  x="$(xml)"
  grep -q "mode='host-passthrough'" <<<"$x" \
    && grep -q '<iothreads>1</iothreads>' <<<"$x" \
    && grep -q "cache='none'.*discard='unmap'" <<<"$x" \
    && grep -q '<source type=.memfd' <<<"$x" \
    && grep -q '<streaming mode=.off' <<<"$x" \
    && grep -q "device='virtio-vga'" <<<"$x" \
    && grep -q "<input type='tablet' bus='virtio'>" <<<"$x" \
    && grep -q "<input type='keyboard' bus='virtio'>" <<<"$x" \
    && grep -q '<rng model=.virtio' <<<"$x"
}
case "$MODE" in
  --check|--verify)
    check && printf 'PASS: Windows KVM performance configuration\n' || { printf 'FAIL: Windows KVM performance configuration\n' >&2; exit 1; }
    ;;
  --apply)
    [[ "$(virsh domstate "$VM_NAME")" == 'shut off' ]] || { printf 'shut down VM first\n' >&2; exit 1; }
    virt-xml "$VM_NAME" --edit --memorybacking source_type=memfd --define >/dev/null
    virt-xml "$VM_NAME" --edit --graphics spice,streaming.mode=off --define >/dev/null
    if ! grep -q "<input type='tablet' bus='virtio'>" <<<"$(xml)"; then
      virt-xml "$VM_NAME" --add-device --input tablet,bus=virtio --define >/dev/null
    fi
    if ! grep -q "<input type='keyboard' bus='virtio'>" <<<"$(xml)"; then
      virt-xml "$VM_NAME" --add-device --input keyboard,bus=virtio --define >/dev/null
    fi
    check
    ;;
  *) printf 'usage: %s --check|--apply|--verify\n' "$0" >&2; exit 2 ;;
esac

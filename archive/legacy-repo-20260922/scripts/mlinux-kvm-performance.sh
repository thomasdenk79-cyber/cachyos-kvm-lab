#!/usr/bin/env bash
set -Eeuo pipefail

# Apply reversible, host-side graphics tuning for a libvirt SPICE guest.

VM_NAME="${LIBVIRT_VM_NAME:-mlinux-ubuntu2404}"
RENDER_NODE="${LIBVIRT_RENDER_NODE:-/dev/dri/renderD128}"
VIRGL_MAX_HOSTMEM="${LIBVIRT_VIRGL_MAX_HOSTMEM:-1073741824}"
VIRGL_HOSTMEM="${LIBVIRT_VIRGL_HOSTMEM:-268435456}"
SPICE_STREAMING_MODE="${LIBVIRT_SPICE_STREAMING_MODE:-off}"
VCPU_SOCKETS="${LIBVIRT_VCPU_SOCKETS:-1}"
VCPU_CORES="${LIBVIRT_VCPU_CORES:-8}"
VCPU_THREADS="${LIBVIRT_VCPU_THREADS:-1}"

usage() { printf '%s\n' "Usage: LIBVIRT_VM_NAME=name $(basename "$0") --check|--apply|--verify"; }
log() { printf '[mlinux-kvm-performance] %s\n' "$*"; }

domain_exists() { virsh -c qemu:///system dominfo "$VM_NAME" >/dev/null 2>&1; }

check_host() {
  command -v virt-xml >/dev/null && [[ -e "$RENDER_NODE" ]] \
    && pacman -Q virglrenderer qemu-desktop spice >/dev/null 2>&1
}

inactive_xml() { virsh -c qemu:///system dumpxml --inactive "$VM_NAME"; }

check_config() {
  local xml
  xml="$(inactive_xml)"
  grep -q 'accel3d=.yes' <<<"$xml" \
    && grep -q "device=.virtio-vga-gl." <<<"$xml" \
    && grep -q "gl enable=.yes. rendernode=.\?${RENDER_NODE}" <<<"$xml" \
    && grep -q "streaming mode=.${SPICE_STREAMING_MODE}." <<<"$xml" \
    && grep -q "topology.*sockets=.${VCPU_SOCKETS}." <<<"$xml" \
    && grep -q "topology.*cores=.${VCPU_CORES}." <<<"$xml" \
    && grep -q "topology.*threads=.${VCPU_THREADS}." <<<"$xml" \
    && grep -q "virtio-vga-gl.max_hostmem=${VIRGL_MAX_HOSTMEM}" <<<"$xml" \
    && grep -q "virtio-vga-gl.hostmem=${VIRGL_HOSTMEM}" <<<"$xml" \
    && grep -q 'virtio-tablet-pci,bus=pcie.0,addr=0x7' <<<"$xml" \
    && grep -q 'virtio-keyboard-pci,bus=pcie.0,addr=0x8' <<<"$xml" \
    && grep -q 'SPICE_GSTREAMER_PREFER_NVIDIA' <<<"$xml" \
    && grep -q 'port=.5901. autoport=.no. listen=.127.0.0.1.' <<<"$xml" \
    && grep -q 'listen type=.address. address=.127.0.0.1.' <<<"$xml"
}

check_guest_stack_hint() {
  log 'Guest acceptance requires virtio_gpu_dri.so and OpenGL renderer virgl; llvmpipe is a failure'
}

set_host_cpu_performance() {
  if command -v powerprofilesctl >/dev/null 2>&1; then
    powerprofilesctl set performance || log 'WARNING: could not select the performance power profile'
  fi
  if command -v cpupower >/dev/null 2>&1; then
    if sudo -n cpupower frequency-set -g performance >/dev/null 2>&1; then
      log 'Host CPU governor set to performance'
    else
      log 'WARNING: cpupower governor was not changed (passwordless sudo required)'
    fi
  fi
}

apply_config() {
  set_host_cpu_performance
  virt-xml -c qemu:///system "$VM_NAME" --edit \
    --video virtio,accel3d=yes --define >/dev/null
  virt-xml -c qemu:///system "$VM_NAME" --edit \
    --vcpus "sockets=${VCPU_SOCKETS},cores=${VCPU_CORES},threads=${VCPU_THREADS}" --define >/dev/null
  virt-xml -c qemu:///system "$VM_NAME" --edit \
    --xml './devices/video/model/@device=virtio-vga-gl' --define >/dev/null
  virt-xml -c qemu:///system "$VM_NAME" --edit \
    --xml './devices/graphics/@port=5901' \
    --xml './devices/graphics/@autoport=no' \
    --xml './devices/graphics/@listen=127.0.0.1' \
    --xml './devices/graphics/listen/@type=address' \
    --xml './devices/graphics/listen/@address=127.0.0.1' \
    --xml 'xpath.delete=./devices/graphics/listen[@type="socket"]' \
    --define >/dev/null
  virt-xml -c qemu:///system "$VM_NAME" --edit \
    --graphics "spice,gl.enable=yes,gl.rendernode=${RENDER_NODE}" --define >/dev/null
  virt-xml -c qemu:///system "$VM_NAME" --edit \
    --graphics "spice,streaming.mode=${SPICE_STREAMING_MODE}" --define >/dev/null
  if ! grep -q "virtio-vga-gl.max_hostmem=${VIRGL_MAX_HOSTMEM}" <<<"$(inactive_xml)"; then
    # QEMU applies -global defaults before the virtio-vga device is created.
    virt-xml -c qemu:///system "$VM_NAME" --edit \
      --qemu-commandline="-global virtio-vga-gl.max_hostmem=${VIRGL_MAX_HOSTMEM}" \
      --define >/dev/null
  fi
  if ! grep -q "virtio-vga-gl.hostmem=${VIRGL_HOSTMEM}" <<<"$(inactive_xml)"; then
    virt-xml -c qemu:///system "$VM_NAME" --edit \
      --qemu-commandline="-global virtio-vga-gl.hostmem=${VIRGL_HOSTMEM}" \
      --define >/dev/null
  fi
  if ! grep -q 'SPICE_GSTREAMER_PREFER_NVIDIA' <<<"$(inactive_xml)"; then
    virt-xml -c qemu:///system "$VM_NAME" --edit \
      --qemu-commandline='env=SPICE_GSTREAMER_PREFER_NVIDIA=1' \
      --define >/dev/null
  fi
  if ! grep -q 'virtio-tablet-pci,bus=pcie.0,addr=0x7' <<<"$(inactive_xml)"; then
    virt-xml -c qemu:///system "$VM_NAME" --edit \
      --qemu-commandline='-device virtio-tablet-pci,bus=pcie.0,addr=0x7' \
      --define >/dev/null
  fi
  if ! grep -q 'virtio-keyboard-pci,bus=pcie.0,addr=0x8' <<<"$(inactive_xml)"; then
    virt-xml -c qemu:///system "$VM_NAME" --edit \
      --qemu-commandline='-device virtio-keyboard-pci,bus=pcie.0,addr=0x8' \
      --define >/dev/null
  fi
  log "Applied persistent virtio-vga/VirGL/SPICE tuning; streaming=${SPICE_STREAMING_MODE}, hostmem=${VIRGL_HOSTMEM}, max_hostmem=${VIRGL_MAX_HOSTMEM} bytes"
  check_guest_stack_hint
  if [[ "$(virsh -c qemu:///system domstate "$VM_NAME")" != 'shut off' ]]; then
    log 'VM is running; graphics changes take effect after a clean full shutdown'
  fi
}

case "${1:---check}" in
  --help|-h) usage ;;
  --check)
    domain_exists && check_host && check_config && log 'performance configuration ready' \
      || { log 'performance configuration incomplete'; exit 1; }
    ;;
  --apply) domain_exists && check_host || { log 'VM, virt-xml, rendernode, or host packages missing'; exit 1; }; apply_config ;;
  --verify)
    domain_exists && check_host && check_config && log 'VERIFY_PASS' \
      || { log 'VERIFY_FAIL'; exit 1; }
    ;;
  *) usage >&2; exit 2 ;;
esac

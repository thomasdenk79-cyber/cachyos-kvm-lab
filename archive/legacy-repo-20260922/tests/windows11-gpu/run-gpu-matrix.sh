#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
VM_NAME=${WIN11_GPU_VM_NAME:-windows11-generic-test}
LOG_ROOT=${WIN11_GPU_LOG_ROOT:-$HOME/system-setup/logs/windows11-gpu}
RUN_DIR=$LOG_ROOT/$(date +%Y%m%d-%H%M%S)
BASE_XML=$RUN_DIR/base-domain.xml

usage() { printf 'Usage: %s --check|--profile PROFILE|--matrix\n' "$(basename "$0")"; }
log() { printf '[win11-gpu] %s\n' "$*"; }

check_host() {
  command -v virsh >/dev/null
  command -v qemu-system-x86_64 >/dev/null
  command -v nvidia-smi >/dev/null
  test -r /dev/dri/renderD128
  test -r /dev/dri/renderD129
  virsh -c qemu:///system dominfo "$VM_NAME" >/dev/null
}

wait_off() {
  for _ in {1..45}; do
    [[ $(virsh -c qemu:///system domstate "$VM_NAME") == 'shut off' ]] && return 0
    sleep 1
  done
  return 1
}

stop_vm() {
  [[ $(virsh -c qemu:///system domstate "$VM_NAME") == 'shut off' ]] || virsh -c qemu:///system shutdown "$VM_NAME" >/dev/null 2>&1 || true
  wait_off
}

start_vm() {
  virsh -c qemu:///system start "$VM_NAME" >/dev/null
  sleep 12
  [[ $(virsh -c qemu:///system domstate "$VM_NAME") == 'running' ]]
}

restore_base() {
  stop_vm
  virsh -c qemu:///system define "$BASE_XML" >/dev/null
  start_vm
}

apply_profile() {
  local profile=$1 xml="$RUN_DIR/$profile.xml"
  cp "$BASE_XML" "$xml"
  case "$profile" in
    baseline-intel-virtio-vga) : ;;
    virtio-vga-gl-intel) sed -i "s/device='virtio-vga'/device='virtio-vga-gl'/" "$xml" ;;
    nvidia-spice-virtio-vga) sed -i "s#rendernode='/dev/dri/renderD128'#rendernode='/dev/dri/renderD129'#" "$xml" ;;
    qxl-spice) sed -i "/<acceleration accel3d='yes'\/>/d; s#<model type='virtio' heads='1' primary='yes' device='virtio-vga'>#<model type='qxl' heads='1' primary='yes'>#" "$xml" ;;
    *) log "unknown profile: $profile"; return 2 ;;
  esac
  virsh -c qemu:///system define "$xml" >/dev/null
}

record_profile() {
  local profile=$1
  {
    echo "timestamp=$(date --iso-8601=seconds)"
    echo "profile=$profile"
    echo "host_kernel=$(uname -srvm)"
    echo "qemu=$(qemu-system-x86_64 --version | head -n1)"
    echo "libvirt=$(virsh --version)"
    echo '--- effective XML ---'; virsh -c qemu:///system dumpxml "$VM_NAME"
    echo '--- QEMU arguments ---'; ps -C qemu-system-x86_64 -o args= | grep "$VM_NAME" || true
    echo '--- NVIDIA ---'; nvidia-smi --query-gpu=name,driver_version,utilization.gpu --format=csv,noheader || true
    echo '--- guest agent ---'; virsh -c qemu:///system qemu-agent-command "$VM_NAME" '{"execute":"guest-info"}' || true
  } > "$RUN_DIR/$profile.stack.log" 2>&1
  virsh -c qemu:///system screenshot "$VM_NAME" "$RUN_DIR/$profile.png" --screen 0 > "$RUN_DIR/$profile.screenshot.log" 2>&1 || true
}

run_profile() {
  local profile=$1
  log "profile=$profile"
  stop_vm; apply_profile "$profile"
  if ! start_vm; then echo 'result=START_FAIL' > "$RUN_DIR/$profile.result"; restore_base; return 1; fi
  record_profile "$profile"
  if grep -q 'no surface\|eglInitialize failed\|render node init failed' "$RUN_DIR/$profile.stack.log" "$RUN_DIR/$profile.screenshot.log" 2>/dev/null; then echo 'result=FAIL' > "$RUN_DIR/$profile.result"; else echo 'result=BOOTED; guest-3d=UNVERIFIED' > "$RUN_DIR/$profile.result"; fi
}

case ${1:---check} in
  --help|-h) usage ;;
  --check) check_host; log CHECK_PASS ;;
  --profile|--matrix)
    check_host; mkdir -p "$RUN_DIR"; chmod 700 "$RUN_DIR"; virsh -c qemu:///system dumpxml --inactive "$VM_NAME" > "$BASE_XML"
    if [[ $1 == --profile ]]; then run_profile "${2:?missing profile}"; else for p in baseline-intel-virtio-vga virtio-vga-gl-intel nvidia-spice-virtio-vga qxl-spice; do run_profile "$p" || true; done; fi
    restore_base; log "results=$RUN_DIR" ;;
  *) usage >&2; exit 2 ;;
esac

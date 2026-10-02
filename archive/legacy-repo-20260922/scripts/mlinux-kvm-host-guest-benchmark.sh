#!/usr/bin/env bash
set -Eeuo pipefail

# Compare identical OpenGL/CPU workloads on the CachyOS host and Ubuntu guest.

VM_NAME="${LIBVIRT_VM_NAME:-mlinux-ubuntu2404}"
VM_IP="${LIBVIRT_VM_IP:-192.168.122.38}"
VM_USER="${LIBVIRT_VM_USER:-z000g9hu}"
SSH_KEY="${LIBVIRT_SSH_KEY:-$HOME/.ssh/mlinux-ubuntu2404_agent}"
LOG_ROOT="${HOST_GUEST_BENCHMARK_LOG_ROOT:-$HOME/system-setup/logs/mlinux-ubuntu2404-gpu/host-guest-$(date +%Y%m%d-%H%M%S)}"
SIZES=(1920x1080 3840x2160)

log() { printf '[host-guest-benchmark] %s\n' "$*"; }
ssh_guest() { ssh -q -o BatchMode=yes -o StrictHostKeyChecking=no -o LogLevel=ERROR -i "$SSH_KEY" "$VM_USER@$VM_IP" "$@"; }

mkdir -p "$LOG_ROOT"
command -v glmark2 >/dev/null
command -v sysbench >/dev/null
[[ -r "$SSH_KEY" ]]
ssh_guest 'test -x /usr/local/sbin/mlinux-guest-virgl-benchmark || test -x /tmp/mlinux-guest-virgl-benchmark.sh'

{
  echo "timestamp=$(date --iso-8601=seconds)"
  echo "host_kernel=$(uname -srvm)"
  . /etc/os-release 2>/dev/null || true
  echo "host_os=${PRETTY_NAME:-unknown} ${VERSION_ID:-unknown}"
  nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || true
  DISPLAY="${DISPLAY:-:0}" glxinfo -B 2>&1 || true
} >"$LOG_ROOT/host-stack.log"

ssh_guest 'uname -srvm; . /etc/os-release; printf "guest_os=%s %s\\n" "$PRETTY_NAME" "$VERSION_ID"; DISPLAY=:0 XAUTHORITY=/run/user/1000/gdm/Xauthority glxinfo -B 2>&1; vulkaninfo --summary 2>&1 | grep -E "deviceName|driverName|driverInfo" || true' >"$LOG_ROOT/guest-stack.log" 2>&1

for size in "${SIZES[@]}"; do
  log "host size=$size"
  timeout 120 env DISPLAY=:0 glmark2 --off-screen --size "$size" \
    -b build:use-vbo=false -b build:use-vbo=true --results fps:cpu \
    2>&1 | tee "$LOG_ROOT/host-glmark2-$size.log"
  log "guest size=$size"
  ssh_guest "VIRGL_BENCHMARK_SIZE='$size' DISPLAY=:0 XAUTHORITY=/run/user/1000/gdm/Xauthority /usr/local/sbin/mlinux-guest-virgl-benchmark --run" \
    2>&1 | tee "$LOG_ROOT/guest-glmark2-$size.log"
done

log 'host CPU'
sysbench cpu --threads=8 --time=20 run 2>&1 | tee "$LOG_ROOT/host-sysbench.log"
log 'guest CPU'
ssh_guest 'sysbench cpu --threads=8 --time=20 run' 2>&1 | tee "$LOG_ROOT/guest-sysbench.log"
log "results=$LOG_ROOT"

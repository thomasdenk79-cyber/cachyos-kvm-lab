#!/usr/bin/env bash
set -Eeuo pipefail

# Run a guest VirGL benchmark while sampling host and guest resource usage.

VM_NAME="${LIBVIRT_VM_NAME:-mlinux-ubuntu2404}"
VM_IP="${LIBVIRT_VM_IP:-192.168.122.38}"
VM_USER="${LIBVIRT_VM_USER:-z000g9hu}"
SSH_KEY="${LIBVIRT_SSH_KEY:-$HOME/.ssh/mlinux-ubuntu2404_agent}"
GUEST_SCRIPT="${LIBVIRT_GUEST_BENCHMARK:-/tmp/mlinux-guest-virgl-benchmark.sh}"
SIZE="${VIRGL_BENCHMARK_SIZE:-1280x720}"
CSV_FILE="${VIRGL_HOST_BENCHMARK_CSV:-/tmp/virgl-host-$(date +%Y%m%d-%H%M%S).csv}"
PUPPET_SETTLE_TIMEOUT="${VIRGL_PUPPET_SETTLE_TIMEOUT:-300}"
SKIP_PUPPET_WAIT="${VIRGL_SKIP_PUPPET_WAIT:-0}"

usage() {
  cat <<'EOF'
Usage: mlinux-kvm-virgl-benchmark.sh --check|--run [--size WxH] [--csv FILE]

The CSV contains host CPU, QEMU CPU, guest CPU, Intel Render/3D and NVIDIA GPU.
The guest script must be installed at /tmp/mlinux-guest-virgl-benchmark.sh.
EOF
}

log() { printf '[kvm-virgl-benchmark] %s\n' "$*"; }

ssh_guest() {
  ssh -q -o BatchMode=yes -o StrictHostKeyChecking=no -o LogLevel=ERROR \
    -i "$SSH_KEY" "$VM_USER@$VM_IP" "$@"
}

host_cpu_snapshot() {
  awk '/^cpu / { total=0; for (i=2; i<=8; i++) total += $i; idle=$5+$6; print total, idle; exit }' /proc/stat
}

guest_cpu_snapshot() {
  ssh_guest "awk '/^cpu / { total=0; for (i=2; i<=8; i++) total += \$i; idle=\$5+\$6; print total, idle; exit }' /proc/stat"
}

percent_delta() {
  awk -v t1="$1" -v i1="$2" -v t2="$3" -v i2="$4" \
    'BEGIN { dt=t2-t1; if (dt <= 0) print "0.0"; else printf "%.1f", 100*(dt-(i2-i1))/dt }'
}

intel_gpu_busy() {
  local probe
  probe="$(mktemp /tmp/intel-gpu-sample.XXXXXX)"
  sudo -n timeout --signal=INT --kill-after=1s 2s \
    intel_gpu_top -J -s 1000 -o - >"$probe" 2>/dev/null || true
  jq -r '.[-1].engines["Render/3D"].busy // "NA"' "$probe" 2>/dev/null || printf 'NA\n'
}

nvidia_gpu_busy() {
  nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null \
    | head -n1 | tr -d ' ' || printf 'NA\n'
}

check_requirements() {
  command -v virsh >/dev/null
  command -v ssh >/dev/null
  command -v jq >/dev/null
  command -v intel_gpu_top >/dev/null
  command -v nvidia-smi >/dev/null
  [[ -r "$SSH_KEY" ]]
  virsh -c qemu:///system dominfo "$VM_NAME" >/dev/null
  ssh_guest "test -x '$GUEST_SCRIPT'"
}

wait_for_guest_quiet() {
  local elapsed=0 stable=0 applying
  log 'Waiting for Puppet configuration to settle before benchmarking'
  while ((elapsed < PUPPET_SETTLE_TIMEOUT)); do
    applying="$(ssh_guest "ps -eo args= | grep -F 'puppet agent: applying configuration' | grep -v grep || true")"
    if [[ -z "$applying" ]]; then
      stable=$((stable + 1))
      ((stable >= 3)) && { log 'Guest settled'; return 0; }
    else
      stable=0
      log 'Puppet is still applying configuration'
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  log "Guest did not settle within ${PUPPET_SETTLE_TIMEOUT}s"
  return 1
}

run_benchmark() {
  local qemu_pid htotal hidle gtotal gidle htotal2 hidle2 gtotal2 gidle2
  local hcpu gcpu qcpu igpu ngpu guest_log guest_pid
  guest_log="${CSV_FILE%.csv}.guest.log"
  qemu_pid="$(pgrep -f -- "qemu-system.*guest=${VM_NAME}" | head -n1)"
  [[ -n "$qemu_pid" ]]
  read -r htotal hidle <<<"$(host_cpu_snapshot)"
  read -r gtotal gidle <<<"$(guest_cpu_snapshot)"
  printf 'timestamp,host_cpu_pct,qemu_cpu_pct,guest_cpu_pct,intel_render3d_pct,nvidia_gpu_pct\n' >"$CSV_FILE"
  log "CSV: $CSV_FILE"
  ssh_guest "VIRGL_BENCHMARK_SIZE='$SIZE' DISPLAY=:0 XAUTHORITY=/run/user/1000/gdm/Xauthority '$GUEST_SCRIPT' --run" \
    >"$guest_log" 2>&1 &
  guest_pid=$!
  while kill -0 "$guest_pid" 2>/dev/null; do
    sleep 1
    read -r htotal2 hidle2 <<<"$(host_cpu_snapshot)"
    read -r gtotal2 gidle2 <<<"$(guest_cpu_snapshot)"
    hcpu="$(percent_delta "$htotal" "$hidle" "$htotal2" "$hidle2")"
    gcpu="$(percent_delta "$gtotal" "$gidle" "$gtotal2" "$gidle2")"
    qcpu="$(ps -p "$qemu_pid" -o pcpu= | xargs || printf 'NA')"
    igpu="$(intel_gpu_busy)"
    ngpu="$(nvidia_gpu_busy)"
    printf '%s,%s,%s,%s,%s,%s\n' "$(date --iso-8601=seconds)" "$hcpu" "$qcpu" "$gcpu" "$igpu" "$ngpu" | tee -a "$CSV_FILE"
    htotal="$htotal2"; hidle="$hidle2"; gtotal="$gtotal2"; gidle="$gidle2"
  done
  wait "$guest_pid" || true
  log "Guest log: $guest_log"
  tail -n 12 "$guest_log"
}

case "${1:---check}" in
  --help|-h) usage ;;
  --check) check_requirements; log 'CHECK_PASS' ;;
  --run)
    shift
    while (($#)); do
      case "$1" in
        --size) SIZE="${2:?missing size}"; shift 2 ;;
        --csv) CSV_FILE="${2:?missing csv path}"; shift 2 ;;
        *) usage >&2; exit 2 ;;
      esac
    done
    check_requirements
    if [[ "$SKIP_PUPPET_WAIT" == 1 ]]; then
      log 'WARNING: running while Puppet may still be applying configuration'
    else
      wait_for_guest_quiet
    fi
    run_benchmark
    ;;
  *) usage >&2; exit 2 ;;
esac

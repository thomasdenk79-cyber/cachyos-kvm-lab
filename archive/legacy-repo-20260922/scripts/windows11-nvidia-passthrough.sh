#!/usr/bin/env bash
set -Eeuo pipefail

# Reversible libvirt VFIO assignment for the mobile NVIDIA GPU and its HDMI audio.
DOMAIN="${WIN11_PASSTHROUGH_DOMAIN:-windows11-generic-test}"
GPU="${WIN11_PASSTHROUGH_GPU:-0000:01:00.0}"
AUDIO="${WIN11_PASSTHROUGH_AUDIO:-0000:01:00.1}"
MODE="${1:---check}"

[[ $EUID -eq 0 ]] || { printf 'run with sudo\n' >&2; exit 1; }
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

hostdev_xml() {
  local addr="$1" rest bus slotfunc bus slot func
  rest="${addr#0000:}"; bus="${rest%%:*}"; slotfunc="${rest#*:}"
  slot="${slotfunc%%.*}"; func="${slotfunc##*.}"
  cat <<EOF
<hostdev mode='subsystem' type='pci' managed='yes'>
  <source>
    <address domain='0x0000' bus='0x${bus}' slot='0x${slot}' function='0x${func}'/>
  </source>
</hostdev>
EOF
}
xml() { virsh dumpxml --inactive "$DOMAIN"; }
has_addr() {
  local rest bus slotfunc slot func
  rest="${1#0000:}"; bus="${rest%%:*}"; slotfunc="${rest#*:}"
  slot="${slotfunc%%.*}"; func="${slotfunc##*.}"
  xml | grep -q "bus='0x${bus}'.*slot='0x${slot}'.*function='0x${func}'"
}
check() {
  local group members
  group="$(basename "$(readlink -f "/sys/bus/pci/devices/$GPU/iommu_group")")"
  members="$(find "/sys/kernel/iommu_groups/$group/devices" -maxdepth 1 -type l -printf '%f\n' | sort)"
  grep -qx '0000:01:00.0' <<<"$members" && grep -qx '0000:01:00.1' <<<"$members" || {
    printf 'FAIL: IOMMU group %s lacks GPU/audio:\n%s\n' "$group" "$members" >&2; return 1;
  }
  while read -r member; do
    case "$member" in 0000:01:00.0|0000:01:00.1) ;; *)
      [[ "$(cat "/sys/bus/pci/devices/$member/class")" == 0x060400 ]] || {
        printf 'FAIL: unexpected non-bridge member %s in IOMMU group %s\n' "$member" "$group" >&2; return 1;
      } ;;
    esac
  done <<<"$members"
  has_addr "$GPU" && has_addr "$AUDIO"
}
case "$MODE" in
  --check|--verify)
    check && printf 'PASS: NVIDIA GPU/audio passthrough configured\n' || { printf 'FAIL: NVIDIA passthrough not configured\n' >&2; exit 1; }
    ;;
  --apply)
    [[ "$(virsh domstate "$DOMAIN")" == 'shut off' ]] || { printf 'shut down VM first\n' >&2; exit 1; }
    if ! has_addr "$GPU"; then hostdev_xml "$GPU" > "$tmpdir/gpu.xml"; virsh attach-device "$DOMAIN" "$tmpdir/gpu.xml" --config >/dev/null; fi
    if ! has_addr "$AUDIO"; then hostdev_xml "$AUDIO" > "$tmpdir/audio.xml"; virsh attach-device "$DOMAIN" "$tmpdir/audio.xml" --config >/dev/null; fi
    check
    ;;
  --rollback)
    [[ "$(virsh domstate "$DOMAIN")" == 'shut off' ]] || { printf 'shut down VM first\n' >&2; exit 1; }
    for addr in "$GPU" "$AUDIO"; do hostdev_xml "$addr" > "$tmpdir/device.xml"; virsh detach-device "$DOMAIN" "$tmpdir/device.xml" --config >/dev/null 2>&1 || true; done
    ! has_addr "$GPU" && ! has_addr "$AUDIO"
    printf 'PASS: NVIDIA passthrough rolled back\n'
    ;;
  *) printf 'usage: %s --check|--apply|--rollback|--verify\n' "$0" >&2; exit 2 ;;
esac

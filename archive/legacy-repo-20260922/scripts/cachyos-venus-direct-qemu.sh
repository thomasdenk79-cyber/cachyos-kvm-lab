#!/usr/bin/env bash
set -Eeuo pipefail

# Disposable direct-QEMU Venus runner. Run as root. It uses a qcow2 overlay,
# so guest writes do not reach the libvirt base image.

DOMAIN="${CACHYOS_VENUS_DOMAIN:-cachyos-venus-test}"
RUN_DIR="${CACHYOS_VENUS_RUN_DIR:-/tmp/cachyos-direct-nvidia}"
BASE_IMAGE="${CACHYOS_VENUS_IMAGE:-/var/lib/libvirt/images/cachyos-venus-test.qcow2}"
NVRAM="/var/lib/libvirt/qemu/nvram/${DOMAIN}_VARS.fd"
HOST_ICD="${CACHYOS_VENUS_HOST_ICD:-/usr/share/vulkan/icd.d/nvidia_icd.json}"
RENDER_NODE="${CACHYOS_VENUS_RENDER_NODE:-/dev/dri/renderD129}"
VENUS="${CACHYOS_VENUS_ENABLE:-1}"
PAT="${CACHYOS_VENUS_PAT:-1}"
SPICE_GL="${CACHYOS_VENUS_SPICE_GL:-1}"
DUAL_DISPLAY="${CACHYOS_VENUS_DUAL_DISPLAY:-0}"
MODE="${1:---check}"

[[ $EUID -eq 0 ]] || { printf 'run with sudo\n' >&2; exit 1; }
uuid="$(virsh domuuid "$DOMAIN")"
tpm_base="/var/lib/libvirt/swtpm/$uuid/tpm2"
overlay="$RUN_DIR/overlay.qcow2"

case "$MODE" in
  --check)
    test -r "$BASE_IMAGE"
    test -r "$NVRAM"
    test -d "$tpm_base"
    printf 'direct PAT QEMU prerequisites OK\n'
    ;;
  --start)
    [[ "$(virsh domstate "$DOMAIN")" == 'shut off' ]] || { printf 'stop libvirt domain first\n' >&2; exit 1; }
    install -d -m 0700 "$RUN_DIR"
    [[ -e "$overlay" ]] || qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMAGE" "$overlay"
    [[ -e "$RUN_DIR/OVMF_VARS.fd" ]] || install -m 0600 "$NVRAM" "$RUN_DIR/OVMF_VARS.fd"
    if [[ ! -e "$RUN_DIR/tpm/tpm2-00.permall" ]]; then
      install -d -m 0700 "$RUN_DIR/tpm"
      cp -a "$tpm_base"/. "$RUN_DIR/tpm/"
    fi
    accel=kvm
    [[ "$PAT" == 1 ]] && accel=kvm,honor-guest-pat=on
    gpu=virtio-vga-gl,hostmem=4G,blob=on
    [[ "$VENUS" == 1 ]] && gpu+=,venus=on
    video_args=(-device "$gpu")
    if [[ "$DUAL_DISPLAY" == 1 ]]; then
      gpu=virtio-gpu-gl,hostmem=4G,blob=on
      [[ "$VENUS" == 1 ]] && gpu+=,venus=on
      video_args=(-vga std -device "$gpu")
    fi
    spice="port=5901,addr=127.0.0.1,disable-ticketing=on,gl=on,rendernode=$RENDER_NODE"
    [[ "$SPICE_GL" == 0 ]] && spice="port=5901,addr=127.0.0.1,disable-ticketing=on,gl=off"
    swtpm socket --tpm2 --tpmstate dir="$RUN_DIR/tpm" \
      --ctrl type=unixio,path="$RUN_DIR/swtpm.sock",mode=0600 \
      --log file="$RUN_DIR/swtpm.log" --daemon
    VK_DRIVER_FILES="$HOST_ICD" \
      qemu-system-x86_64 -name cachyos-direct-nvidia \
      -machine pc-q35-11.1 -accel "$accel" -cpu host -m 16G -smp 8 \
      -drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd \
      -drive if=pflash,format=raw,unit=1,file="$RUN_DIR/OVMF_VARS.fd" \
      -drive file="$overlay",if=virtio,format=qcow2 \
      -chardev socket,id=chrtpm,path="$RUN_DIR/swtpm.sock" -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0 \
      "${video_args[@]}" \
      -spice "$spice" \
      -audiodev driver=none,id=none -device virtio-net-pci,netdev=n0 \
      -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2223-:22 \
      -device virtio-tablet-pci -device virtio-keyboard-pci \
      -device virtio-serial-pci \
      -chardev spicevmc,id=vdagent,name=vdagent \
      -device virtserialport,chardev=vdagent,name=com.redhat.spice.0 \
      -display egl-headless,gl=on \
      -qmp unix:"$RUN_DIR/qmp.sock",server=on,wait=off \
      >"$RUN_DIR/qemu-nvidia.log" 2>&1 &
    echo $! > "$RUN_DIR/qemu.pid"
    printf 'started overlay=%s\n' "$overlay"
    ;;
  --stop)
    pid="$(cat "$RUN_DIR/qemu.pid")"
    kill "$pid" 2>/dev/null || true
    printf 'stopped direct QEMU; overlay retained at %s\n' "$overlay"
    ;;
  *)
    printf 'usage: %s --check|--start|--stop\n' "$0" >&2
    exit 2
    ;;
esac

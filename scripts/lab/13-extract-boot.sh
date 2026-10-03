#!/usr/bin/env bash
# 13-extract-boot.sh - extrahiert Kernel/Initrd fuer seriellen Direktboot.
set -euo pipefail
cd "$(dirname "$0")"; source ./env.sh
for pair in "ubuntu:$LAB_ISO_UBUNTU:/casper" "cachyos:$LAB_ISO_CACHY:/arch/boot/x86_64"; do
  name="${pair%%:*}"; rest="${pair#*:}"; iso="${rest%%:*}"; sub="${rest##*:}"
  [ -f "$LAB_WORK/boot/$name/vmlinuz" ] && { echo "$name boot ok"; continue; }
  M=$(mktemp -d); sudo mount -o ro,loop "$iso" "$M"
  mkdir -p "$LAB_WORK/boot/$name"
  case "$name" in
    ubuntu) sudo cp "$M$sub/vmlinuz" "$LAB_WORK/boot/ubuntu/vmlinuz"
            sudo cp "$M$sub/initrd" "$LAB_WORK/boot/ubuntu/initrd" ;;
    cachyos) sudo cp "$M$sub/vmlinuz-linux-cachyos" "$LAB_WORK/boot/cachyos/vmlinuz"
             sudo cp "$M$sub/initramfs-linux-cachyos.img" "$LAB_WORK/boot/cachyos/initramfs" ;;
  esac
  sudo umount "$M"; rmdir "$M"; echo "$name extrahiert"
done

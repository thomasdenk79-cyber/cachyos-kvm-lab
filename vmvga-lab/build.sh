#!/usr/bin/env bash
# VMVGA-Lab Build – reproduzierbarer Ablauf (Status: bereits ausgefuehrt 2026-10-13,
# Skript dient als Dokumentation + frischer Nachbau).
# Pinnes: QEMU 11.1.1 (sha256 079ffbff8a7111bbc89022107cbabf3bbfd614d5fc9d7cc675991196aca12482)
#         qemu-vmvga tag v1.03 (commit 073c4dc64e49dd082c70f249dd883cba7ea93f43)
#         DXVK Native 3.1.1 (Asset dxvk-native-3.1.1-steamrt-sniper.tar.gz)
set -euo pipefail
cd "$(dirname "$0")"
[ -d qemu-11.1.1 ] || { curl -fLO https://download.qemu.org/qemu-11.1.1.tar.xz; echo "079ffbff8a7111bbc89022107cbabf3bbfd614d5fc9d7cc675991196aca12482  qemu-11.1.1.tar.xz" | sha256sum -c; tar xf qemu-11.1.1.tar.xz; }
git -C qemu-vmvga rev-parse HEAD | grep -q '^073c4dc64e49dd082c70f249dd883cba7ea93f43$' || { rm -rf qemu-vmvga; git clone --depth 1 --branch v1.03 https://github.com/qemus/qemu-vmvga.git; }
cp -a qemu-vmvga/hw/. qemu-11.1.1/hw/          # komplettes hw/-Overlay laut README
mkdir -p build && cd build
../qemu-11.1.1/configure \
  --prefix=/opt/qemu-vmvga/11.1.1-vmvga1.03 \
  --target-list=x86_64-softmmu --enable-kvm \
  --enable-spice --enable-sdl --enable-gtk --enable-opengl \
  --enable-slirp --enable-vnc-jpeg --enable-seccomp --enable-linux-aio \
  --enable-cap-ng --enable-png --enable-zstd \
  --disable-modules --disable-docs --disable-install-blobs --disable-linux-user --disable-werror
ninja -j"$(nproc)" qemu-system-x86_64 qemu-img qemu-storage-daemon qemu-pr-helper
sudo ninja install
echo "INSTALL: /opt/qemu-vmvga/11.1.1-vmvga1.03/bin/qemu-system-x86_64"

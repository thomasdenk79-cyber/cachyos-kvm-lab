#!/usr/bin/env bash
# DXVK Native 3.1.1 privat nach /opt/dxvk-vmvga installieren (sonst nirgends).
set -euo pipefail
cd "$(dirname "$0")"
V=3.1.1; A=dxvk-native-${V}-steamrt-sniper.tar.gz
[ -f "$A" ] || curl -fL -o "$A" "https://github.com/doitsujin/dxvk/releases/download/v${V}/${A}"
sudo mkdir -p /opt/dxvk-vmvga/${V}
sudo tar xf "$A" -C /opt/dxvk-vmvga/${V} --strip-components=1
# Pflicht-Check gemaess Geraet (dlopst exakt diese SONAMEs):
sudo ls -l /opt/dxvk-vmvga/${V}/lib64/libdxvk_d3d9.so.0 /opt/dxvk-vmvga/${V}/lib64/libdxvk_d3d11.so.0 \
  || sudo find /opt/dxvk-vmvga/${V} -name 'libdxvk_d3*.so.0' -printf '%p\n'
echo "LD Pfad fuer VM-Prozesse: $(sudo find /opt/dxvk-vmvga/${V} -name libdxvk_d3d9.so.0 -printf '%h\n' | head -1)"

#!/usr/bin/env bash
# Preflight-Check des gebauten Binaries (Pflicht vor Gaststart, Auftrag Punkt 1).
set -u
Q=/opt/qemu-vmvga/11.1.1-vmvga1.03/bin/qemu-system-x86_64
LOG="$(dirname "$0")/logs"; mkdir -p "$LOG"
{
  echo "== --version =="; "$Q" --version | head -2
  echo "== -accel help =="; "$Q" -accel help
  echo "== -device vmvga,help =="; QEMU_MODULE_DIR=/nonexistent "$Q" -device vmvga,help
  echo "== -display help =="; "$Q" -display help
  echo "== ldd =="; ldd "$Q" | grep -E 'not found' && echo "FEHLENDE BIBLIOTHEKEN!" || echo "ldd ok"
  echo "== DXVK-Native dlopen-Test (gleicher Pfad wie Geraet) =="
  python3 - <<'EOF'
import ctypes, os
for p in ("/opt/dxvk-vmvga/3.1.1/lib64/libdxvk_d3d9.so.0",):
    if not os.path.exists(p):
        import subprocess
        out = subprocess.run(["find","/opt/dxvk-vmvga","-name",os.path.basename(p)],capture_output=True,text=True).stdout.split()
        p = out[0] if out else p
    try:
        ctypes.CDLL(p); print("dlopen OK:", p)
    except OSError as e:
        print("dlopen FEHLER:", p, e)
EOF
} 2>&1 | tee "$LOG/preflight-$(date +%Y%m%d-%H%M).log"

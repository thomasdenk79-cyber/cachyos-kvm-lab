#!/usr/bin/env bash
set -Eeuo pipefail
VM=${WIN11_VM:-win11-siemens}; GPU_ID=${WIN11_NVIDIA_GPU_ID:-10de:1fb8}; AUDIO_ID=${WIN11_NVIDIA_AUDIO_ID:-10de:10fa}
CMDLINE=/etc/kernel/cmdline; MODPROBE=/etc/modprobe.d/win11-nvidia-vfio.conf; MKINIT=/etc/mkinitcpio.conf
die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }; R(){ if (( EUID == 0 )); then "$@"; else sudo "$@"; fi; }
command -v virsh >/dev/null || die 'virsh fehlt'
[[ "$(R virsh domstate "$VM" 2>/dev/null | head -1)" == 'shut off' ]] || die "$VM muss ausgeschaltet sein"
R install -d -m 0755 /etc/modprobe.d
current=$(cat "$CMDLINE" 2>/dev/null || true)
for arg in intel_iommu=on iommu=pt; do grep -qw -- "$arg" <<<"$current" || current+=" $arg"; done
R install -m 0644 /dev/stdin "$CMDLINE" <<<"$current"
R install -m 0644 /dev/stdin "$MODPROBE" <<EOT
# NVIDIA Quadro T2000 passthrough for $VM
options vfio-pci ids=$GPU_ID,$AUDIO_ID disable_vga=1
softdep nvidia pre: vfio-pci
softdep nouveau pre: vfio-pci
EOT
if ! grep -q '^MODULES=.*vfio_pci' "$MKINIT"; then R sed -i 's/^MODULES=(/MODULES=(vfio_pci vfio vfio_iommu_type1 /' "$MKINIT"; fi
R mkinitcpio -P
R virsh dumpxml --inactive "$VM" > "configs/${VM}-nvidia-passthrough.xml"
python3 - "configs/${VM}-nvidia-passthrough.xml" <<'PY'
import sys
from xml.etree import ElementTree as ET
p=sys.argv[1]; root=ET.parse(p).getroot(); dev=root.find('devices')
for bus, slot, fn in [('01','00','0'),('01','00','1')]:
 h=ET.SubElement(dev,'hostdev',{'mode':'subsystem','type':'pci','managed':'yes'}); s=ET.SubElement(h,'source'); ET.SubElement(s,'address',{'domain':'0x0000','bus':'0x'+bus,'slot':'0x'+slot,'function':'0x'+fn})
ET.ElementTree(root).write(p,encoding='unicode')
PY
R chmod 0644 "configs/${VM}-nvidia-passthrough.xml"
printf 'Prepared. Reboot required before VFIO can claim %s and %s.\n' "$GPU_ID" "$AUDIO_ID"

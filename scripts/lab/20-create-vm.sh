#!/usr/bin/env bash
# 20-create-vm.sh <vm-name> - legt Disk + Domain via virt-install --print-xml an.
# Win11: SATA-Disk + e1000 (Inbox-Treiber, Stabilen-Weg aus open-items), OVMF + swtpm.
set -euo pipefail
cd "$(dirname "$0")"; source ./env.sh
VM=${1:?vm-name fehlt}
[ -f "$CREDS_FILE" ] || { echo "00-init-host.sh zuerst ausfuehren"; exit 1; }
DISK="$LAB_DISKS/$VM.qcow2"

case "$VM" in
  vm-ubuntu)
    [ -f "$LAB_ISO_UBUNTU" ] || { echo "Ubuntu-ISO fehlt"; exit 1; }
    [ -f "$LAB_SEED/ubuntu-seed.iso" ] || ../lab/10-seed-ubuntu.sh
    virt-install --connect qemu:///system --print-xml --name "$VM" \
      --memory $VM_MEM_MIB --vcpus $VM_VCPUS --cpu host-passthrough,disable=vmx --machine q35 \
      --boot uefi --video virtio --graphics none --console pty,target_type=isa-serial \
      --install kernel=$LAB_WORK/boot/ubuntu/vmlinuz,initrd=$LAB_WORK/boot/ubuntu/initrd,kernel_args="boot=casper file=/cdrom/preseed/ubuntu.seed autoinstall console=ttyS0,115200n8" \
      --check disk_size=off --osinfo ubuntu24.04 \
      --disk path="$DISK",size=$VM_DISK_GB,format=qcow2,bus=virtio \
      --disk path="$LAB_ISO_UBUNTU",device=cdrom,readonly=on \
      --disk path="$LAB_SEED/ubuntu-seed.iso",device=cdrom,readonly=on \
      --network network=default,model=virtio,mac=$(vm_mac $VM) > /tmp/$VM.xml
    ;;
  vm-win11)
    [ -f "$LAB_ISO_WIN" ] || { echo "Win11-ISO fehlt"; exit 1; }
    [ -f "$LAB_SEED/win11-seed.iso" ] || ../lab/11-seed-win11.sh
    virt-install --connect qemu:///system --print-xml --name "$VM" \
      --memory $VM_MEM_MIB --vcpus $VM_VCPUS --cpu host-passthrough,disable=vmx --machine q35 \
      --boot uefi --video std --graphics none --console pty,target_type=isa-serial \
      --check disk_size=off --osinfo win11 \
      --disk path="$DISK",size=$VM_DISK_GB,format=qcow2,bus=sata \
      --cdrom "$LAB_ISO_WIN" \
      --disk path="$LAB_ISO_VIRTIO",device=cdrom,readonly=on \
      --disk path="$LAB_SEED/win11-seed.iso",device=cdrom,readonly=on \
      --network network=default,model=e1000,mac=$(vm_mac $VM) > /tmp/$VM.xml
    # vTPM 2.0 (swtpm) ergaenzen, falls nicht vorhanden
    grep -q "<tpm" /tmp/$VM.xml || sed -i 's|<features>|<features>\n    <tpm model="tpm-crb"><backend type="emulator" version="2.0"/></tpm>|' /tmp/$VM.xml
    ;;
  vm-cachyos)
    [ -f "$LAB_ISO_CACHY" ] || { echo "CachyOS-ISO fehlt"; exit 1; }
    [ -f "$LAB_SEED/lab-cachyos.iso" ] || ../lab/12-seed-cachyos.sh
    virt-install --connect qemu:///system --print-xml --name "$VM" \
      --memory $VM_MEM_MIB --vcpus $VM_VCPUS --cpu host-passthrough,disable=vmx --machine q35 \
      --video virtio --graphics none --console pty,target_type=isa-serial \
      --install kernel=$LAB_WORK/boot/cachyos/vmlinuz,initrd=$LAB_WORK/boot/cachyos/initramfs,kernel_args="archisobasedir=arch archisosearchuuid=2026-08-09-15-47-03-00 cow_spacesize=10G copytoram=auto console=ttyS0,115200n8" \
      --check disk_size=off --osinfo archlinux \
      --disk path="$DISK",size=$VM_DISK_GB,format=qcow2,bus=virtio \
      --disk path="$LAB_ISO_CACHY",device=cdrom,readonly=on \
      --disk path="$LAB_SEED/lab-cachyos.iso",device=cdrom,readonly=on \
      --network network=default,model=virtio,mac=$(vm_mac $VM) > /tmp/$VM.xml
    ;;
  *) echo "unbekannt: $VM"; exit 1;;
esac

# virt-install --print-xml liefert 2 Documents: Install-Boot + finale Config
python3 - "$VM" <<'PY'
import sys,re,html
vm=sys.argv[1]
raw=open(f"/tmp/{vm}.xml").read()
docs=re.findall(r"<domain.*?</domain>", raw, re.S)
inst,final=docs[0],docs[-1]
inst=inst.replace("isa-serial","serial"); final=final.replace("isa-serial","serial")
inst=inst.replace('type="std"','type="vga"'); final=final.replace('type="std"','type="vga"')
if vm=="vm-win11":
    inst=inst.replace("<on_reboot>destroy</on_reboot>","<on_reboot>restart</on_reboot>")
    inst=inst.replace(chr(60)+'boot order='+chr(39)+'1'+chr(39)+'/>'+chr(62),'')
    
    inst=re.sub(chr(60)+'boot dev=[^>]*/>', '', inst)   # OS-Bootelement raus (libvirt-Synthese)
    # Win-ISO (sdb, erste CD) bekommt Bootorder 1; Reboot-Entfall via 26-win-eject-watcher
    i=inst.find('Windows11_Client')
    j=inst.find('</disk>', i)
    inst=inst[:j] + "<boot order='1'/>" + inst[j:]
    inst=re.sub(r"<cpu mode=\"host-model\"\s*/>", "<cpu mode='host-passthrough'><feature name='vmx' policy='disable'/></cpu>", inst)
    inst=re.sub(r"<feature name='vmx' policy=\"require\"/>", "<feature name='vmx' policy='disable'/>", inst)
    inst=re.sub(r'<feature name="vmx" policy="require"/>', "<feature name='vmx' policy='disable'/>", inst)
if vm=="vm-cachyos":
    f2=inst
    f2=re.sub(r"\s*<kernel>[^<]+</kernel>", "", f2)
    f2=re.sub(r"\s*<initrd>[^<]+</initrd>", "", f2)
    f2=re.sub(r"\s*<cmdline>[^<]+</cmdline>", "", f2)
    f2=re.sub(r"<disk[^>]*device=.cdrom.[^>]*>.*?</disk>", "", f2, flags=re.S)
    f2=f2.replace(" ","").replace(' firmware="efi"',"")
    f2=f2.replace("<on_reboot>restart</on_reboot>","<on_reboot>restart</on_reboot>")
    open(f"/tmp/{vm}-final.xml","w").write(f2)
else:
    open(f"/tmp/{vm}-final.xml","w").write(final)
open(f"/tmp/{vm}-install.xml","w").write(inst)
PY
# virt-install --print-xml kopiert Kernel/Initrd nicht: manuell an referenzierten Pfad legen
for f in kernel initrd; do
  src=""; dst=$(sudo virsh -c qemu:///system 2>/dev/null; grep -oP "<$f>\K[^<]+" /tmp/$VM-install.xml 2>/dev/null | head -1) || true
done
python3 - "$VM" <<'PYX'
import sys,subprocess,re
vm=sys.argv[1]
x=open(f"/tmp/{vm}-install.xml").read()
m=re.search(r"<kernel>([^<]+)</kernel>",x)
n=re.search(r"<initrd>([^<]+)</initrd>",x)
if m and n:
    srck="/srv/vms/work/boot/"+("ubuntu" if "ubuntu" in vm else "cachyos")+"/"
    isoc="ubuntu" if "ubuntu" in vm else "cachyos"
    subprocess.run(["sudo","cp",f"/srv/vms/work/boot/{isoc}/vmlinuz",m.group(1)],check=True)
    ext="initrd" if isoc=="ubuntu" else "initramfs"
    subprocess.run(["sudo","cp",f"/srv/vms/work/boot/{isoc}/{ext}",n.group(1)],check=True)
    print("kernel/initrd bereitgestellt")
PYX
sudo virsh -c qemu:///system define /tmp/$VM-install.xml
sudo virsh -c qemu:///system start "$VM"
echo "$VM: Install-Boot gestartet (final-XML bereit: /tmp/$VM-final.xml)"

#!/usr/bin/env bash
set -u
mode=${1:---check}
if [[ "$mode" == "--help" ]]; then echo "Usage: $0 [--check|--verify]"; exit 0; fi
[[ "$mode" == --check || "$mode" == --verify ]] || exit 2
echo "KVM baseline ($mode)"
for x in qemu-system-x86_64 virsh virt-manager swtpm; do
  if command -v "$x" >/dev/null 2>&1; then printf '%-18s %s\n' "$x" "$(command -v "$x")"; else printf '%-18s missing\n' "$x"; fi
done
[[ -e /dev/kvm ]] && echo 'kvm-device=present' || echo 'kvm-device=missing'
printf 'libvirtd='; systemctl is-active libvirtd 2>/dev/null || echo inactive
printf 'libvirt-session='; virsh -c qemu:///session list --all 2>&1 | head -1 || true
printf 'libvirt-system='; virsh -c qemu:///system list --all 2>&1 | head -1 || true
echo 'windows-media=not-provided'
echo 'windows-license=not-verified'
echo 'vfio=not-configured'

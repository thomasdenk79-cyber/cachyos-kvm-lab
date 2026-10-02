#!/usr/bin/env bash
set -Eeuo pipefail

# Prepare a Windows VM for repeatable Intune test resets and offline backups.
DOMAIN="${WIN11_INTUNE_DOMAIN:-windows11-generic-test}"
BACKUP_ROOT="${WIN11_INTUNE_BACKUP_ROOT:-/home/z000g9hu/system-setup/backups/windows11-generic-test}"
DISK="/var/lib/libvirt/images/windows11-generic-test.qcow2"
NVRAM="/var/lib/libvirt/qemu/nvram/${DOMAIN}_VARS.fd"
UUID="$(virsh domuuid "$DOMAIN")"
TPM="/var/lib/libvirt/swtpm/$UUID/tpm2"
MODE="${1:---check}"

[[ $EUID -eq 0 ]] || { printf 'run with sudo\n' >&2; exit 1; }
check() { test -r "$DISK" && test -r "$NVRAM" && test -d "$TPM"; }
case "$MODE" in
  --check)
    check && printf 'PASS: Windows Intune backup inputs present\n' || exit 1
    ;;
  --backup)
    [[ "$(virsh domstate "$DOMAIN")" == 'shut off' ]] || { printf 'VM must be shut off\n' >&2; exit 1; }
    check
    stamp="$(date +%Y%m%d-%H%M%S)"; dest="$BACKUP_ROOT/$stamp"
    install -d -m 0700 "$dest"
    virsh dumpxml --inactive "$DOMAIN" > "$dest/domain.xml"
    cp --reflink=auto --sparse=always "$DISK" "$dest/windows11-generic-test.qcow2"
    cp --preserve=all "$NVRAM" "$dest/OVMF_VARS.fd"
    cp -a "$TPM" "$dest/tpm2"
    sha256sum "$dest/windows11-generic-test.qcow2" "$dest/OVMF_VARS.fd" > "$dest/SHA256SUMS"
    printf 'backup=%s\n' "$dest"
    ;;
  --identity)
    [[ "$(virsh domstate "$DOMAIN")" == 'shut off' ]] || { printf 'VM must be shut off\n' >&2; exit 1; }
    xml="$(mktemp)"; trap 'rm -f "$xml"' EXIT
    virsh dumpxml --inactive "$DOMAIN" > "$xml"
    compact="${UUID//-/}"; serial="WIN11-${compact^^}"
    virt-xml "$DOMAIN" --edit --sysinfo \
      "system.manufacturer=QEMU,system.product=KVM Windows 11,system.serial=${serial},system.uuid=${UUID}" \
      --define >/dev/null
    virsh dumpxml --inactive "$DOMAIN" > "$xml"
    if ! grep -q "${serial}-DISK" "$xml"; then
      sed -i "/<target dev='sdc' bus='sata'\/>/i\\      <serial>${serial}-DISK</serial>" "$xml"
      virsh define "$xml" >/dev/null
    fi
    printf 'identity_serial=%s\n' "$serial"
    ;;
  --verify)
    x="$(virsh dumpxml --inactive "$DOMAIN")"
    grep -q '<smbios mode=.sysinfo' <<<"$x" && grep -q '<serial>WIN11-' <<<"$x" && check
    printf 'PASS: Windows Intune identity and backup inputs verified\n'
    ;;
  *) printf 'usage: %s --check|--backup|--identity|--verify\n' "$0" >&2; exit 2 ;;
esac

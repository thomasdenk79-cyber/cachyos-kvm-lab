#!/usr/bin/env bash
set -Eeuo pipefail

# Create a complete offline Windows VM backup and a ZIP archive.
DOMAIN="${WIN11_BACKUP_DOMAIN:-windows11-generic-test}"
ROOT="${WIN11_BACKUP_ROOT:-/home/z000g9hu/system-setup/backups/windows11-generic-test}"
DISK="/var/lib/libvirt/images/windows11-generic-test.qcow2"
NVRAM="/var/lib/libvirt/qemu/nvram/${DOMAIN}_VARS.fd"
UUID="$(virsh domuuid "$DOMAIN")"
TPM="/var/lib/libvirt/swtpm/$UUID/tpm2"
MODE="${1:---check}"

[[ $EUID -eq 0 ]] || { printf 'run with sudo\n' >&2; exit 1; }
check_inputs() { test -r "$DISK" && test -r "$NVRAM" && test -d "$TPM"; }

case "$MODE" in
  --check)
    [[ "$(virsh domstate "$DOMAIN")" == 'shut off' ]] && check_inputs
    printf 'PASS: Windows VM is offline and backup inputs are present\n'
    ;;
  --create)
    [[ "$(virsh domstate "$DOMAIN")" == 'shut off' ]] || { printf 'VM must be shut off\n' >&2; exit 1; }
    check_inputs
    stamp="$(date +%Y%m%d-%H%M%S)"
    dest="$ROOT/$stamp"
    install -d -m 0700 "$dest"
    virsh dumpxml --inactive "$DOMAIN" > "$dest/domain.xml"
    cp --reflink=auto --sparse=always "$DISK" "$dest/windows11-generic-test.qcow2"
    cp --preserve=all "$NVRAM" "$dest/OVMF_VARS.fd"
    cp -a "$TPM" "$dest/tpm2"
    {
      printf 'domain=%s\nuuid=%s\ncreated=%s\n' "$DOMAIN" "$UUID" "$(date --iso-8601=seconds)"
      printf 'disk=%s\n' "$DISK"
      printf 'nvram=%s\ntpm=%s\n' "$NVRAM" "$TPM"
      printf 'windows_iso='; virsh dumpxml --inactive "$DOMAIN" | sed -n "s#.*<source file='\([^']*Win[^']*\.iso\)'/>.*#\1#p" | head -1
      printf 'virtio_iso='; virsh dumpxml --inactive "$DOMAIN" | sed -n "s#.*<source file='\([^']*virtio-win[^']*\.iso\)'/>.*#\1#p" | head -1
    } > "$dest/MANIFEST.txt"
    (cd "$dest" && sha256sum domain.xml windows11-generic-test.qcow2 OVMF_VARS.fd > SHA256SUMS)
    cat > "$dest/RESTORE-HOWTO.txt" <<'EOF'
Windows-11-VM Restore
=====================
1. Ensure the domain is shut off: sudo virsh destroy windows11-generic-test (only if it is a disposable test state).
2. Verify SHA256SUMS with: sha256sum -c SHA256SUMS.
3. Copy windows11-generic-test.qcow2 to /var/lib/libvirt/images/.
4. Copy OVMF_VARS.fd to /var/lib/libvirt/qemu/nvram/windows11-generic-test_VARS.fd.
5. Restore the TPM directory to /var/lib/libvirt/swtpm/<domain-uuid>/tpm2/.
6. Define the saved domain.xml: sudo virsh define domain.xml.
7. Start: sudo virsh start windows11-generic-test.
Never change the domain UUID, SMBIOS serial, disk serial, MAC, NVRAM, or TPM after Intune enrollment.
EOF
    # tar.xz uses the xz LZMA2 codec and preserves VM metadata.
    archive="$ROOT/windows11-generic-test-$stamp.tar.xz"
    tar -C "$ROOT" --xz -cf "$archive" "$stamp"
    tar -tJf "$archive" >/dev/null
    printf 'backup=%s\narchive=%s\n' "$dest" "$archive"
    ;;
  --verify)
    latest="$(find "$ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)"
    [[ -n "$latest" ]] && (cd "$latest" && sha256sum -c SHA256SUMS >/dev/null)
    archive="$(find "$ROOT" -maxdepth 1 -type f -name '*.tar.xz' -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)"
    [[ -n "$archive" ]] && tar -tJf "$archive" >/dev/null
    printf 'PASS: latest Windows VM backup and tar.xz (LZMA2) verified\n'
    ;;
  *) printf 'usage: %s --check|--create|--verify\n' "$0" >&2; exit 2 ;;
esac

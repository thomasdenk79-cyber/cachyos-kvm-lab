#!/usr/bin/env bash
set -Eeuo pipefail

# Single-file backup/restore for libvirt guests.  ZVOL disks are stored as a
# zfs send stream; file-backed disks are copied as files.  NVRAM, vTPM state,
# and the exact domain XML are included as well.

MODE=""
VM_NAME=""
ARCHIVE=""
FORCE=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/libvirt-vm-backup.sh backup  VM_NAME ARCHIVE.tar.zst
  scripts/libvirt-vm-backup.sh restore ARCHIVE.tar.zst [--force]

backup  requires the VM to be shut off and stores disks, XML, NVRAM and vTPM.
restore requires --force when the VM or its ZVOL already exists.
USAGE
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '[vm-backup] %s\n' "$*"; }
as_root() { if (( EUID == 0 )); then "$@"; else sudo "$@"; fi; }

[[ $# -ge 1 ]] || { usage >&2; exit 2; }
MODE="$1"; shift
case "$MODE" in
  backup)
    [[ $# -ge 2 ]] || { usage >&2; exit 2; }
    VM_NAME="$1"; ARCHIVE="$2"; shift 2
    ;;
  restore)
    [[ $# -ge 1 ]] || { usage >&2; exit 2; }
    ARCHIVE="$1"; shift
    ;;
  *) usage >&2; exit 2 ;;
esac
while (($#)); do
  case "$1" in
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

command -v virsh >/dev/null || die 'virsh is required'
command -v python3 >/dev/null || die 'python3 is required'
command -v zstd >/dev/null || die 'zstd is required'
command -v tar >/dev/null || die 'tar is required'

state() { virsh -c qemu:///system domstate "$1" 2>/dev/null | head -1 || true; }

backup_vm() {
  virsh -c qemu:///system dominfo "$VM_NAME" >/dev/null 2>&1 || die "VM not found: $VM_NAME"
  [[ "$(state "$VM_NAME")" == 'shut off' ]] || die "VM must be shut off before backup"
  [[ "$ARCHIVE" = /* ]] || ARCHIVE="$PWD/$ARCHIVE"
  mkdir -p "$(dirname -- "$ARCHIVE")"

  local stage xml manifest disks_json run_id
  stage="$(mktemp -d)"
  run_id="$(date +%Y%m%d-%H%M%S)"
  trap 'rm -rf -- "$stage"' EXIT
  as_root install -d -m 0700 "$stage/disks" "$stage/nvram" "$stage/tpm"
  xml="$stage/domain.xml"
  virsh -c qemu:///system dumpxml "$VM_NAME" > "$xml"
  disks_json="$stage/disks.json"
  python3 - "$xml" > "$disks_json" <<'PY'
import json, sys
from xml.etree import ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
items=[]
for d in root.findall('./devices/disk'):
    if d.get('device') != 'disk':
        continue
    s=d.find('source'); t=d.find('target')
    if s is not None and t is not None:
        items.append({'source': s.get('dev') or s.get('file') or '', 'target': t.get('dev','')})
print(json.dumps(items))
PY
  manifest="$stage/manifest.json"
  python3 - "$xml" "$stage" "$VM_NAME" "$run_id" > "$manifest" <<'PY'
import json, os, sys
from xml.etree import ElementTree as ET
xml, stage, name, run = sys.argv[1:]
root=ET.parse(xml).getroot()
nv=root.find('./os/nvram')
tpm=root.find('./devices/tpm/backend/device')
print(json.dumps({'version':1,'vm_name':name,'run_id':run,
                  'nvram': nv.text if nv is not None else '',
                  'tpm': tpm.get('path','') if tpm is not None else ''}, indent=2))
PY

  local idx=0 source target dataset snap out
  while IFS=$'\t' read -r source target; do
    [[ -n "$source" ]] || continue
    idx=$((idx+1))
    if [[ "$source" == /dev/zvol/* ]]; then
      dataset="${source#/dev/zvol/}"
      zfs list -H -o name "$dataset" >/dev/null 2>&1 || die "ZVOL dataset not found: $dataset"
      snap="${dataset}@vm-backup-${run_id}"
      as_root zfs snapshot "$snap"
      # Always remove the temporary snapshot, including when zfs send or
      # archive creation fails.  Encrypted datasets require a raw send so the
      # stream remains restorable without exposing plaintext.
      trap 'as_root zfs destroy "$snap" >/dev/null 2>&1 || true; rm -rf -- "$stage"' EXIT
      out="$stage/disks/${idx}-${target}.zfs"
      log "Sending ZVOL $dataset"
      as_root zfs send -w "$snap" > "$out"
      as_root zfs destroy "$snap"
      trap 'rm -rf -- "$stage"' EXIT
      python3 - "$manifest" "$idx" "$target" "$dataset" <<'PY'
import json,sys
p,i,t,d=sys.argv[1:]; x=json.load(open(p)); x.setdefault('disks',[]).append({'index':int(i),'target':t,'kind':'zvol','dataset':d,'file':f'disks/{i}-{t}.zfs'}); open(p,'w').write(json.dumps(x,indent=2))
PY
    else
      [[ -f "$source" ]] || die "Disk file not found: $source"
      out="$stage/disks/${idx}-${target}-file"
      as_root cp --reflink=auto --sparse=always -- "$source" "$out"
      as_root chmod 0600 "$out"
      python3 - "$manifest" "$idx" "$target" "$source" <<'PY'
import json,sys
p,i,t,s=sys.argv[1:]; x=json.load(open(p)); x.setdefault('disks',[]).append({'index':int(i),'target':t,'kind':'file','source':s,'file':f'disks/{i}-{t}-file'}); open(p,'w').write(json.dumps(x,indent=2))
PY
    fi
  done < <(python3 - "$disks_json" <<'PY'
import json,sys
for x in json.load(open(sys.argv[1])): print(x['source']+'\t'+x['target'])
PY
)

  local nvram tpm_path
  nvram="$(python3 - "$manifest" -c 'import json,sys; print(json.load(open(sys.argv[1])).get("nvram", ""))')"
  if [[ -n "$nvram" && -f "$nvram" ]]; then as_root cp -- "$nvram" "$stage/nvram/vars.fd"; fi
  tpm_path="$(python3 - "$manifest" -c 'import json,sys; print(json.load(open(sys.argv[1])).get("tpm", ""))')"
  if [[ -n "$tpm_path" && -e "$tpm_path" ]]; then as_root cp -a -- "$tpm_path" "$stage/tpm/state"; fi
  as_root tar --zstd -cf "$ARCHIVE" -C "$stage" manifest.json domain.xml disks nvram tpm
  as_root chown "${SUDO_UID:-$UID}:${SUDO_GID:-$GID}" "$ARCHIVE" 2>/dev/null || true
  log "Backup written: $ARCHIVE"
}

restore_vm() {
  [[ -f "$ARCHIVE" ]] || die "Archive not found: $ARCHIVE"
  local stage manifest name xml
  stage="$(mktemp -d)"; trap 'rm -rf "$stage"' EXIT
  tar --zstd -xf "$ARCHIVE" -C "$stage"
  manifest="$stage/manifest.json"; xml="$stage/domain.xml"
  name="$(python3 - "$manifest" -c 'import json,sys; print(json.load(open(sys.argv[1]))["vm_name"])')"
  if virsh -c qemu:///system dominfo "$name" >/dev/null 2>&1; then
    (( FORCE )) || die "VM exists; use --force to replace it"
    [[ "$(state "$name")" == 'shut off' ]] || die "VM must be shut off before restore"
    virsh -c qemu:///system undefine "$name" --nvram >/dev/null 2>&1 || virsh -c qemu:///system undefine "$name"
  fi
  local disk kind dataset file parent nvram tpm
  while read -r kind dataset file; do
    if [[ "$kind" == zvol ]]; then
      if zfs list -H -o name "$dataset" >/dev/null 2>&1; then
        (( FORCE )) || die "ZVOL exists; use --force to replace it"
        as_root zfs destroy -f "$dataset"
      fi
      parent="${dataset%/*}"; as_root zfs list -H -o name "$parent" >/dev/null 2>&1 || as_root zfs create -p "$parent"
      log "Restoring ZVOL $dataset"
      as_root zfs receive -u "$dataset" < "$stage/$file"
    else
      parent="$(dirname -- "$dataset")"; as_root install -d -m 0755 "$parent"
      (( FORCE )) || [[ ! -e "$dataset" ]] || die "Disk file exists: $dataset"
      as_root cp -- "$stage/$file" "$dataset"
    fi
  done < <(python3 - "$manifest" <<'PY'
import json,sys
for d in json.load(open(sys.argv[1])).get('disks',[]): print(d['kind'], d.get('dataset',d.get('source','')), d['file'])
PY
)
  nvram="$(python3 - "$manifest" -c 'import json,sys; print(json.load(open(sys.argv[1])).get("nvram", ""))')"
  [[ -z "$nvram" ]] || { as_root install -d -m 0755 "$(dirname -- "$nvram")"; as_root cp -- "$stage/nvram/vars.fd" "$nvram"; as_root chown libvirt-qemu:libvirt-qemu "$nvram" 2>/dev/null || true; }
  tpm="$(python3 - "$manifest" -c 'import json,sys; print(json.load(open(sys.argv[1])).get("tpm", ""))')"
  if [[ -n "$tpm" && -d "$stage/tpm/state" ]]; then as_root install -d -m 0700 "$(dirname -- "$tpm")"; as_root cp -a "$stage/tpm/state" "$tpm"; fi
  virsh -c qemu:///system define "$xml" >/dev/null
  log "Restored VM: $name (not started)"
}

case "$MODE" in
  backup) backup_vm ;;
  restore) restore_vm ;;
esac

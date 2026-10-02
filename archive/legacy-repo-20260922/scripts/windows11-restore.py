#!/usr/bin/env python3
"""Restore an existing Windows domain from metadata while preserving identity."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import pwd
import shutil
import subprocess
import tarfile
import xml.etree.ElementTree as ET


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--disk', type=Path, required=True)
    parser.add_argument('--iso-dir', type=Path, required=True)
    parser.add_argument('--work-dir', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    assert os.geteuid() == 0, 'Run with sudo -n'
    assert args.disk.is_file()
    info = json.loads(run('qemu-img', 'info', '--output=json', str(args.disk)))
    assert info['format'] == 'raw', 'Expected verified RAW disk'
    with tarfile.open(args.archive, 'r:xz') as archive:
        names = archive.getnames()
        xml_name = next(n for n in names if n.endswith('/windows-identity/windows11-generic-test.xml'))
        original = archive.extractfile(xml_name).read()
        root = ET.fromstring(original)
        name, uuid = root.findtext('name'), root.findtext('uuid')
        existing = run('virsh', '-c', 'qemu:///system', 'list', '--all', '--name').splitlines()
        if name in existing:
            assert run('virsh', '-c', 'qemu:///system', 'domuuid', name) == uuid
            current = ET.fromstring(run('virsh', '-c', 'qemu:///system', 'dumpxml', name, '--inactive'))
            assert current.find("devices/disk[@device='disk']/source").get('file') == str(args.disk)
            print('Existing restored domain verified; no state overwritten.')
            return
        # QEMU machine versions cannot be migrated backwards unchanged.
        machine = 'pc-q35-8.2'
        assert machine in run('qemu-system-x86_64', '-machine', 'help')
        root.find('os/type').set('machine', machine)
        loader = root.find('os/loader')
        loader.text = '/usr/share/OVMF/OVMF_CODE_4M.secboot.fd'
        loader.attrib.pop('format', None)
        nvram = root.find('os/nvram')
        nvram_path = Path(nvram.text)
        nvram.set('template', '/usr/share/OVMF/OVMF_VARS_4M.fd')
        for key in ('format', 'templateFormat'):
            nvram.attrib.pop(key, None)
        root.find('cpu/topology').attrib.pop('clusters', None)
        for disk in root.findall('devices/disk'):
            source = disk.find('source')
            if disk.get('device') == 'disk':
                source.set('file', str(args.disk))
                disk.find('driver').set('type', 'raw')
            elif source is not None:
                replacement = args.iso_dir / Path(source.get('file')).name
                if replacement.is_file():
                    source.set('file', str(replacement))
                else:
                    disk.remove(source)
        # Windows VirtIO-DOD is 2D; SPICE GL is not a Windows 3D driver.
        gl = root.find('devices/graphics/gl')
        if gl is not None:
            gl.attrib.clear()
            gl.set('enable', 'no')
        model = root.find('devices/video/model')
        model.attrib.pop('device', None)
        accel = model.find('acceleration')
        if accel is not None:
            accel.set('accel3d', 'no')
        profile = root.find('devices/tpm/backend/profile')
        if profile is not None:
            root.find('devices/tpm/backend').remove(profile)
        for label in root.findall('seclabel'):
            root.remove(label)
        # Ensure UUID, SMBIOS, disk serial and MAC are not regenerated.
        original_root = ET.fromstring(original)
        for xpath in ('uuid', 'sysinfo', "devices/disk[@device='disk']/serial", 'devices/interface/mac'):
            assert ET.tostring(root.find(xpath)) == ET.tostring(original_root.find(xpath))
        args.work_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        (args.work_dir / 'original.xml').write_bytes(original)
        ET.indent(root)
        candidate = args.work_dir / 'restored.xml'
        candidate.write_bytes(ET.tostring(root, encoding='utf-8', xml_declaration=True))
        print('Candidate: identity preserved; RAW/SATA; Q35 8.2; original TPM/NVRAM; local SPICE.')
        if not args.apply:
            return
        qemu = pwd.getpwnam('libvirt-qemu')
        tpm = pwd.getpwnam('tss')
        nvram_member = next(n for n in names if n.endswith('/libvirt/nvram/' + nvram_path.name))
        nvram_data = archive.extractfile(nvram_member).read()
        assert len(nvram_data) == Path('/usr/share/OVMF/OVMF_VARS_4M.fd').stat().st_size
        assert not nvram_path.exists(), 'Never replace existing UEFI state'
        nvram_path.parent.mkdir(parents=True, exist_ok=True)
        nvram_path.write_bytes(nvram_data)
        nvram_path.chmod(0o600)
        os.chown(nvram_path, qemu.pw_uid, qemu.pw_gid)
        tpm_root = Path('/var/lib/libvirt/swtpm') / uuid
        assert not tpm_root.exists(), 'Never replace existing TPM state'
        tpm_root.mkdir(parents=True, mode=0o700)
        os.chown(tpm_root, tpm.pw_uid, tpm.pw_gid)
        members = [n for n in names if f'/libvirt/swtpm/{uuid}/' in n and n.endswith('.permall')]
        assert members, 'TPM state absent'
        for member in members:
            rel = member.split(f'/libvirt/swtpm/{uuid}/', 1)[1]
            assert '..' not in Path(rel).parts
            target = tpm_root / rel
            target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            os.chown(target.parent, tpm.pw_uid, tpm.pw_gid)
            target.write_bytes(archive.extractfile(member).read())
            target.chmod(0o600)
            os.chown(target, tpm.pw_uid, tpm.pw_gid)
        print(run('virsh', '-c', 'qemu:///system', 'define', '--validate', str(candidate)))
        print('Restored. Start separately after disk permissions and firewall verification.')


if __name__ == '__main__':
    main()

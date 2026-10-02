# Win11/ZFS Neustart-Checkliste

Stand: 2026-09-27

Die VM `win11-siemens` ist definiert und absichtlich ausgeschaltet. Vor dem
Host-Neustart sind keine weiteren VM-Änderungen nötig.

## Gesicherter Sollzustand

- Domain: `win11-siemens`
- UUID: `e39af3f0-0d5f-4932-8934-9fe33d19ce86`
- SMBIOS-Serial: `WIN11-E39AF3F00D5F493289349FE33D19CE86`
- Disk-Serial: `WIN11-E39AF3F00D5F493289349FE33D19CE86-DISK`
- MAC: `52:54:00:df:a5:d1`
- ZVOL: `zpcachyos/vms/win11`, 200G fest reserviert, `volblocksize=64K`
- ZVOL: `compression=zstd-1`, `sync=standard`, `primarycache=all`
- VM: 16GiB RAM, 8 vCPU, Host-Passthrough, Hugepages
- Storage: VirtIO-SCSI, `cache=none`, `io=io_uring`, `discard=unmap`
- Medien: `/run/media/z000g9hu/Ventoy/ISO/Imported/`

## Vor dem Neustart

```bash
sudo virsh -c qemu:///system domstate win11-siemens
sudo virsh -c qemu:///system dumpxml --inactive win11-siemens > ~/win11-siemens.xml.backup
zpool status -x
cat /proc/sys/vm/nr_hugepages
```

Die Ausgabe sollte `shut off`, `all pools are healthy` und `8192` enthalten.

## Nach dem Neustart

```bash
uname -r
systemctl is-active libvirtd
zpool status -x
zfs get volsize,volblocksize,compression,sync,primarycache zpcachyos/vms/win11
cat /proc/sys/vm/nr_hugepages
sudo virsh -c qemu:///system dominfo win11-siemens
```

Danach die VM nur für die Windows-Installation starten:

```bash
sudo virsh -c qemu:///system start win11-siemens
```

## Wenn der Bootmanager nicht startet

1. Im UEFI-Bootmenü den vorhandenen Eintrag `cachyos`/GRUB auswählen.
2. Nicht formatieren und den ZFS-Pool nicht importieren oder upgraden.
3. Von einem CachyOS- oder SystemRescue-Stick booten und zuerst prüfen:

```bash
zpool import
zpool import -N zpcachyos
zpool status -x zpcachyos
```

4. Die VM-Identität nicht neu erzeugen. Die gesicherte XML verwenden und nur
   den Pfad zum ZVOL prüfen.

ZFSBootMenu/rEFInd sind installiert, aber der aktuell laufende Bootloader ist
weiterhin GRUB. Deshalb bleibt GRUB der Rückfallweg.

## Offene Arbeiten nach erfolgreichem Neustart

- Windows-Installation aus der eingebundenen Multi-Edition-ISO durchführen.
- VirtIO-Treiber aus `virtio-win.iso` laden.
- In Windows RDP nur nach gewünschter Unternehmensrichtlinie aktivieren.
- Danach normale VM-Start-/Shutdown-Prüfung und Sicherung der Domain-XML.

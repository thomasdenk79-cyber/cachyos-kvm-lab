# VM-Lab: CachyOS, Ubuntu 24.04, Windows 11

Der Einstieg ist [`scripts/vm-lab.sh`](../scripts/vm-lab.sh). Standardmäßig wird
nur vorbereitet: ISOs werden nach `/var/lib/libvirt/boot` geladen und Vorlagen
nach `.vm-lab/` geschrieben. `--create` gibt es bewusst nicht; der sichere
Aufruf ist:

```bash
./scripts/vm-lab.sh prepare
./scripts/vm-lab.sh create
```

Alle drei Gäste werden mit 16 GiB RAM, 4 vCPUs und einer dynamisch wachsenden
QCOW2-Disk mit maximal 200 GiB sowie virtio-Disk/NIC angelegt. Es werden keine
ZVOLs verwendet. Der reale Speicherverbrauch der QCOW2-Dateien wächst nur mit
den geschriebenen Gastdaten.
Das sind Host-Kapazitätswerte pro VM; nicht alle drei sollten gleichzeitig auf
einem Host mit knappem freien RAM laufen. Werte können über `VM_LAB_RAM_MIB`,
`VM_LAB_VCPUS` und `VM_LAB_DISK_GIB` überschrieben werden.

Nach einem erfolgreichen SR-IOV-Testboot weist `create` standardmäßig die drei
VFs `0000:00:02.1`, `.2` und `.3` den Gästen CachyOS, Ubuntu und Windows 11 zu.
Die physische GPU `0000:00:02.0` bleibt am Host. Die Zuordnung kann über
`IGPU_VF_CACHYOS`, `IGPU_VF_UBUNTU` und `IGPU_VF_WIN11` geändert werden.
`create` wird abgebrochen, wenn die erwartete VF noch nicht existiert.

Der vorbereitende SR-IOV-Schritt ist separat:

```bash
./scripts/intel-igpu-sriov-experiment.sh prepare
# über systemd-boot einmalig „CachyOS (Intel iGPU SR-IOV experiment)“ booten
./scripts/intel-igpu-sriov-experiment.sh status
echo 3 | sudo tee /sys/devices/pci0000:00/0000:00:02.0/sriov_numvfs
./scripts/vm-lab.sh create
```

Ubuntu erhält eine Cloud-Init-Vorlage. CachyOS bleibt beim ersten Start
interaktiv. Die Windows-Unattend-Datei ist absichtlich nur ein sicherer
Template-Rahmen: ISO, Edition, Lizenz und lokales Kennwort müssen vor dem
Einsatz gesetzt werden. Das Skript lädt keine inoffizielle Windows-Quelle.

## Intel-iGPU / IOMMU

`prepare` erzeugt `.vm-lab/boot/vm-lab-iommu.conf`. Erst nach Prüfung von
`/boot/loader/entries` kann dieser Eintrag mit `sudo ./scripts/vm-lab.sh
install-boot` installiert werden. Der aktuelle Standard-Boot-Eintrag bleibt
unverändert; der Testeintrag nutzt `intel_iommu=on iommu=pt`. Die iGPU wird
nicht automatisch an vfio gebunden. Intel GVT-g ist auf aktuellen Kerneln
nicht allgemein verfügbar; der sichere erste Test ist iGPU-IOMMU plus virtio.

## Nachbereitung

```bash
./scripts/vm-lab.sh status
virsh console ubuntu24-vm
virsh shutdown <name>
virsh undefine <name> --remove-all-storage   # bewusst destruktiv
```

## VM-Lab 2026-10 (3er-Autobau)

Neuer Skript-Satz: `scripts/lab/` (Kaltstart nach Host-Neustart: `./rebuild-all.sh`,
Detailzustand: `handover.md`, Fakten: `memory.md`).

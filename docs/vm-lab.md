# VM-Lab: CachyOS, Ubuntu 24.04, Windows 11

Der Einstieg ist [`scripts/vm-lab.sh`](../scripts/vm-lab.sh). Standardmäßig wird
nur vorbereitet: ISOs werden nach `/var/lib/libvirt/boot` geladen und Vorlagen
nach `.vm-lab/` geschrieben. `--create` gibt es bewusst nicht; der sichere
Aufruf ist:

```bash
./scripts/vm-lab.sh prepare
./scripts/vm-lab.sh create
```

Alle drei Gäste werden mit 16 GiB RAM, 4 vCPUs und virtio-Disk/NIC angelegt.
Das sind Host-Kapazitätswerte pro VM; nicht alle drei sollten gleichzeitig auf
einem Host mit knappem freien RAM laufen. Werte können über `VM_LAB_RAM_MIB`,
`VM_LAB_VCPUS` und `VM_LAB_DISK_GIB` überschrieben werden.

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

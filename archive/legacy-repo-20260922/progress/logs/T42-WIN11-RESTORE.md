# T42-WIN11-RESTORE

2026-09-22: Vorhandene 200-GB-RAW-Platte von `/media/z000g9hu/data/vm-images/windows11.raw` eingebunden. Für libvirt wurden Kopien unter `/var/lib/libvirt/images/windows11.raw` und `/var/lib/libvirt/boot/` angelegt, Eigentümer `libvirt-qemu:kvm`, Modus 0640. Die ursprüngliche Domain-Identität blieb erhalten; `windows11-generic-test` startet und läuft. UFW-Regeln für virbr0 DHCP/DNS/Forwarding angelegt, UFW bleibt deaktiviert.

# Migration aus workstation-setup

Stand: 2026-10-02

Die dedizierten KVM-/libvirt-/QEMU-/Win11-Dateien wurden aus
`workstation-setup` hierher übertragen. Die Verzeichnisstruktur der Quellen
bleibt für bekannte Pfade erhalten.

## Aktive Einstiege

- `scripts/vm-lab.sh` und `docs/vm-lab.md`: CachyOS-, Ubuntu- und Win11-Lab
- `scripts/win11-vm.sh`: Win11/libvirt-Profil
- `scripts/libvirt-vm-backup.sh`: VM-Backup
- `scripts/win11-nvidia-passthrough-prepare.sh`: Passthrough-Hilfe
- `configs/`, `config/sysctl.d/`, `winre/`: VM-Konfiguration und Gastreparatur

`archive/` und die Analyse-Artefakte sind historische Referenzen. Sie sind kein
aktiver Ausführungspfad und werden nicht automatisch ausgeführt.

## Herkunft

Quelle: `https://github.com/thomasdenk79-cyber/workstation-setup`
Quellstand beim Umzug: `0e0c3f5` plus die lokale Umzugsdokumentation.

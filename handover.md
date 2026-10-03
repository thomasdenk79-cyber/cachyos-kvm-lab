# Handover VM-Lab (2026-10-03, Stand ~07:50)

## Ziel (vom User beauftragt)
3 VMs autonom errichten: `vm-ubuntu`, `vm-cachyos`, `vm-win11`.
Je 12 GiB RAM, 4 vCPU host-passthrough **ohne vmx** (Nested aus, Win11-Problematik),
200 GB dynamisches qcow2. Vollautomatisch: Autoinstall/autounattend, alle Updates,
VirtIO + qemu-guest-agent, SSH + RDP (xrdp) in allen Gästen, Host-Steuerung via
qemu-agent, Remmina-Profile + SSH-Config fertig vorkonfiguriert. Alles skriptiert.

## Infra (fertig, verifiziert)
- Storage: `zpcachyossrv/vms/{disks,iso,seed}` → `/srv/vms/...`
  (recordsize=1M, xattr=sa, atime=off; Pool auf zstd geupgradet – `compatibility=grub2`
  wurde entfernt; **Boot nicht betroffen**, GRUB/rEFInd/ZBM lesen nur `zpcachyos`).
  Nicht noch mal upgraden/umhängen: Dataset-Mount überdeckt vorherige Dateien im Eltern-Dataset.
- libvirt `default`-Netz war nach Migration nicht definiert → neu erstellt
  (192.168.122.0/24, DHCP) + feste Leases: ubuntu=.51, cachyos=.52, win11=.53.
- Pakete: virt-install 5.1, swtpm, edk2-ovmf, expect, remmina, freerdp.
- Secrets (NICHT im Repo): `~/.config/kvm-lab/creds.env` (LAB_VM_PASSWORD),
  SSH-Key `~/.ssh/kvm_lab_ed25519(.pub)`. Gast-User überall: `vmadmin`.

## ISOs in /srv/vms/iso (alle sha256-verifiziert)
- ubuntu-24.04.4-desktop-amd64.iso (6,6G) + ubuntu-24.04.5-live-server-amd64.iso (Reserve)
- cachyos-desktop-linux-260809.iso (sha im Mirror: 959f6577...)
- Windows11_Client_x64_de-de_26300_9457.iso — **Insider Dev 26300**, vom User per Browser geladen
- virtio-win.iso (877 MB, fedorapeople stable)
- Boot-Extrakte für Direktboot: `/srv/vms/work/boot/{ubuntu,cachyos}/{vmlinuz,initrd|initramfs}`
  (`13-extract-boot.sh`)

## Skripte scripts/lab/ (Kommandoüberblick)
- `env.sh` Variablen/MACs/IPs/get_pass/hash_pass(openssl passwd -6, Python 3.14 hat kein crypt)
- `00-init-host.sh` Pakete, Key, Creds, default-Netz + Leases (idempotent, alles mit sudo virsh)
- `10-seed-ubuntu.sh` Autoinstall-CD (Label `autoinstall`, user-data mit storage/late-commands,
  xrdp-startwm dbus-launch gnome-session, lab-post.service → apt full-upgrade → Flag /var/lib/lab-postdone)
- `11-seed-win11.sh` autounattend.xml (de-DE, Disk_Wipe 500M/16M/rest, ImageName „Windows 11 Pro",
  AutoLogon+FirstLogon→task LABPOST, post.ps1: RDP+SSH+VirtIO+qga+PSWindowsUpdate bis done,
  done-Flag C:\Lab\done, dann shutdown)
- `12-seed-cachyos.sh` + `files/cachyos-live.sh` pacstrap-Installer (btrfs @/@home,
  KDE-minimal plasma-desktop+xrdp+qga+sshd, GRUB **BIOS/i386-pc**, lab-post.service)
- `13-extract-boot.sh` Kernel/Initrd-Extraktion aus ISOs
- `20-create-vm.sh` pro VM: virt-install --print-xml → python-Split (doc0=install, doc-1=final),
  isa-serial→serial, std→vga, host-passthrough disable vmx, --check disk_size=off;
  ubuntu/cachyos: `--install kernel=...,initrd=...,kernel_args="..."` (NICHT mit --cdrom mischen!)
  + Kernel-Dateien an referenzierten /var/lib/libvirt/boot-Pfad kopieren;
  win11: OS-boot-Element raus + Win-ISO bootorder=1 + on_reboot restart + tpm-crb/emulator-Backend
  (swtpm) nachreichen. cachyos: --boot **weggelassen** (=SeaBIOS), final-XML = install ohne
  Kernel/CDs/firmware='efi'. Define+Start der install-XML; final liegt bereit.
- `25-advance.sh` bei shut off + eingeloggten CDs: finale XML definieren+starten (idempotent;
  Ubuntu→UEFI-final, CachyOS→SeaBIOS-final, Win11→UEFI-final).
- `26-win-eject-watcher.sh` hält auf reboot-Event, dann sdb/sdc/sdd auswerfen
  (sonst bootet der ISO wieder ins Setup; Log /srv/vms/work/eject-watcher.log).
- `40-post.sh <vm> [min]` wartet guest-ping + Post-Flag, prüft qga/ssh/xrdp/3389/22.
- `50-connect.sh` ssh-config-Block, /etc/hosts, Remmina .remmina (RDP=4, noch nicht
  verifiziert!), xfreerdp .desktop-Fallback.
- `run-all.sh` Orchestrator.
- `rebuild-all.sh` NEU: Kaltstart nach Host-Reboot (siehe unten).

## Live-Status beim letzten Check (~07:45)
- vm-win11: läuft seit ~06:55, qga noch nicht da (PE-Phase), Eject-Watcher scharf.
  Disk noch klein = PE-Phase normal.
- vm-ubuntu: läuft, UEFI-CD-Boot blind (kein serieller Installer-Ausgang, Grub der Desktop-ISO
  schreibt nicht auf ttyS0; Autoinstall läuft trotzdem – beobachten über Disk-Wachstum
  und `virsh screenshot` Farbstatistik; on_reboot destroy → danach `25-advance.sh`).
- vm-cachyos: SeaBIOS+Direktboot frisch gestartet; Serielle Konsole letzter Probe noch
  ohne Ausgabe (Boot durch OVMF? nein SeaBIOS jetzt) → nächster Schritt: Konsolenprobe
  auf `login:` (root leer) und dann `31-drive-cachyos.exp`-Ablauf
  (mount /dev/sr1 && bash /mnt/cdrom/cachyos-live.sh).

## Zu tun (Reihenfolge)
1. CachyOS-Konsole verifizieren; wenn `login:` → expect-Drive ausführen,
   sonst Screenshot/Diagnose (Grub-Arg console=ttyS0,115200n8 gesetzt? cmdline im XML prüfen).
2. Ubuntu-Abschluss: growth→0 & shut off erwarten; 25-advance; 40-post (60–90 min).
3. Win11: done-Flag via 40-post (bis 180 min, mehrere WU-Reboots); danach RDP-Test vom Host.
4. 50-connect.sh + Remmina-Protokoll-ID verifizieren (sonst .desktop-Fallback nutzen).
5. docs/vm-lab.md + README-Verweis auffrischen; memory.md-Fakten: Pool-Upgrade,
   ISO-Löschunfall (--remove-all-storage+ISO-CD!), Insider-Basis 26300, Lab-Zugangsart.
6. Nach Abschluss: 3 VMs herunterfahren (User plant Host-Reboot) – Bootreihenfolge
   final ist uefi/bios je VM in den final-XMLs korrekt.

## Fallstricke (bitte nie wieder)
- `pkill -f <muster>` erschießt den eigenen Shell-String → [B]rackets oder pgrep+feste PID.
- Dataset-MountS vor Datei-Downloads anlegen (ISO lag schon mal unter einem Mount).
- `virsh undefine --remove-all-storage` löscht angehängte ISO-Dateien!
- virt-install 5.x: `--install kernel=...` unverträglich mit `--cdrom` (Argument schluckt kernel_args);
  `--boot bios` gibt es nicht (= Option weglassen); `--check disk_size=off` wegen 200G-virtuell;
  --print-xml kopiert kernel/initrd NICHT → 20-create-vm.sh stellt sie bereit.
- libvirt 12: target type `isa-serial` ⇒ `serial`; video `std` ⇒ `vga`; OS-Boot vs.
  per-Gerät-Boot schließt sich aus (bei bootorder alles aus <os> entfernen).
- Python 3.14: `crypt` entfernt.

## Credentials-Ausgabe für User (nach Abschluss einmal münden)
User vmadmin, Passwort in ~/.config/kvm-lab/creds.env; SSH-Hostaliasse vm-ubuntu/…;
Remmina-Doppelklick-Profile; RDP-Ports .51-.53:3389.

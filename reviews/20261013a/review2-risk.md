# Review 2 – RISK & ROLLBACK – nächtliche Änderungen P16 Gen2 (2026-10-13)

Prüfzeitpunkt: 2026-10-13, Host Kubuntu 24.04, Kernel 7.0.0-38-generic, UEFI-Boot via GRUB (BootCurrent 0004 = Ubuntu/shim).

## Befunde

### R1 – kvm-siemens Snapshot `pre-tune-20261013` | Severity: OK (mit Hinweisen)

**Verifiziert:**
- `virsh snapshot-list`: Snapshot existiert, State shutoff, `Current: yes`, Location **external**, memory snapshot=no (disk-only) – exakt dokumentiert.
- Chain konsistent: `qemu-img info` auf `/var/lib/libvirt/images/kvm-siemens/kvm-siemens.pre-tune-20261013` (111 MiB Overlay, `corrupt: false`) → backing `kvm-siemens.qcow2` (26.6 GiB, `corrupt: false`, keine Intermediate-Lücke). `domblklist` zeigt vda korrekt auf das Overlay – Basis ist eingefroren, alle Writes laufen ins Overlay. Revert ist technisch intakt.
- XML-Backups vorhanden und lesbar: `~/vm-lab/kvm-siemens-backup-20261012-2346.xml` (8 vCPU, Pre-Tune), `kvm-siemens-tuned.xml`, `kvm-venus.xml`. Snapshot-Metadaten enthalten das alte Domain-XML (vcpu=8) → `snapshot-revert` rollt **sowohl Disk als auch Tuning** zurück.
- Platz: /hat 2,2 TB frei; Overlay-Wachstum über Tage unkritisch.

**Verhalten bei Revert nach Tagen Laufzeit:**
- Domain muss shutoff sein (ist sie; bei running verweigert libvirt ohne `--shut-down` bzw. fährt hart herunter). Alle Gast-Disk-Writes seit 12.10. 23:52 werden mit dem Overlay **gelöscht** – bei einem Windows-Gast mit laufendem Intune-Update-Betrieb kann das Guest-Seitig Boot-Dateien inkonsistent machen (ext4/NTFS-Journal übersteht das i.A.; Risiko ist Datenverlust ab Snapshot, genau der Zweck).
- **NVRAM/pflash ist NICHT im disk-only-Snapshot**: UEFI-Bootvariablen (Windows-Boot-Eintrag, Secure-Boot-keys) bleiben auf aktuellem Stand. Da der Eintrag `\EFI\Microsoft\Boot\bootmgfw.efi` stabil bleibt, praktisch harmlos – aber dokumentationswürdig.
- Hinweis: Overlay liegt `root:root 0600`; beim nächsten `virsh start` chown-ed libvirt dynamisch – kein Blocker, aber Grund, vor Revert-Freigabe keinen Manuell-Copy der Disk zu starten.

**Rollback-Kommando:**
`sudo virsh snapshot-revert kvm-siemens pre-tune-20261013` (Domain vorher shutoff), nach Erfolg aufräumen: `sudo virsh snapshot-delete kvm-siemens pre-tune-20261013 --metadata` **Achtung**: `--metadata` verwirft den Rollback-Punkt, nicht die Disk – Reihenfolge im Doku-Abschnitt ist korrekt.

### R2 – IOMMU-GRUB-Änderung | Severity: LOW

**Verifiziert:**
- Backup `/etc/default/grub.bak-pre-iommu-20261013` vorhanden (0640 root, per sudo lesbar). Diff = exakt das Anhängen von ` intel_iommu=on iommu=pt` an `GRUB_CMDLINE_LINUX_DEFAULT` (Größen 1664−1640 = 24 Zeichen = genau der String). Der dokumentierte Revert `sudo sed -i 's/ intel_iommu=on iommu=pt//' /etc/default/grub && sudo update-grub` reproduziert das Backup **zeichenexakt**; alternativ `sudo cp /etc/default/grub.bak-pre-iommu-20261013 /etc/default/grub && sudo update-grub`.
- `update-grub` wurde ausgeführt: `/boot/grub/grub.cfg` (00:15) enthält den Parameter in allen 3 Kernel-Einträgen. Änderung greift erst mit dem ohnehin geplanten Reboot; laufender Kernel hat sie noch nicht (`/proc/cmdline` geprüft).
- **Boot-Kiprisiko gering, Belege:**
  - Intel-IOMMU ist auf diesem Kernel **schon jetzt default-on** aktiv: `/sys/class/iommu/` führt `dmar0`+`dmar1`, 29 IOMMU-Gruppen existieren ohne Kernelparameter. `intel_iommu=on` ist also faktisch ein No-op; neu ist nur `iommu=pt`.
  - Boot-NVMe: beide Kingston FURY hängen am **Intel VMD-Controller 0000:00:0e.0** (`[8086:a77f]`), Devices `10000:e1:00.0`/`10000:e2:00.0`, gemeinsame IOMMU-Gruppe 5, aktiver Default-Domaintyp dort `DMA-FQ`. `iommu=pt` wechselt den Default-Domain auf PASsthrough – der NVMe-Treiber (nvme+vmd, bereits im Initramfs gebunden) bleibt unangetastet; **keine** vfio/vfio_new绑定 ist eingerichtet. Kein Szenario, in dem die Gruppenzugehörigkeit den Boot pfad ändert.
  - Thunderbolt-Blackwell `4b:00.0 [10de:2bb1]` + Audio `4b:00.1`: IOMMU-Anschaltung hotpluged nichts und entbindet nichts; erst ein späteres vfio-bind (bewusst „NOCH nicht eingerichtet“) wäre ein Risiko-Ereignis – das wäre aber ein separater, neuer Schritt.
  - Restrisiko: VT-d-Firmware-Bug mit VMD+Interrupt-Remapping (selten; Remapping läuft hier bereits im Default-On-Betrieb ohne DMAR-Fehler im jetzigen dmesg-Fenster).
- **Notfallpfade verifiziert:** `GRUB_TIMEOUT_STYLE=menu`, `GRUB_TIMEOUT=5` → Menü `e`-Edit (Doku-Zeile 76f) ist tatsächlich erreichbar. Zusätzlich existieren unabhängige Firmware-Entries im BootOrder: `Boot0003 Kubuntu`, `Boot0001/0002 systemd-boot (Linux Boot Manager)` – selbst ein komplett kaputter Ubuntu-GRUB ist über F12 umgehbar, die Grub-Datei ist nie der einzige Bootweg.

**Rollback-Kommando:**
`sudo cp /etc/default/grub.bak-pre-iommu-20261013 /etc/default/grub && sudo update-grub` (äquivalent zum dokumentierten sed; nächster Reboot aktiv).

### R3 – Steam-Snap-Entfernung | Severity: OK

- `snap list --all`: kein steam-Eintrag; `/var/snap/` ohne steam; keine /snap/steam-Mounts (mount-Liste komplett durchgesehen, nur fremde Snaps gemountet).
- `~/snap/` enthält nur noch `firmware-updater` (5 MB) – kein Steam-Datenrest.
- `~/.steam/steam` → Symlink auf `~/.steam/debian-installation`; maßgebliche `steamapps/libraryfolders.vdf` zeigt auf `/home/z000g9hu/.steam/debian-installation` mit **6 Apps** (228980=Steamworks-Runtime, 1284210=GW2, 1493710, 2429640, 3393110, 4183110) – deckungsgleich mit `steamapps/common/` (AION2, Guild Wars 2, Throne and Liberty, Proton-Exp, SteamLinuxRuntime, …). Bestand 275 GB. Keine dangling Referenzen auf Snap-Pfade in den VDFs.
- Die leere `config/libraryfolders.vdf` ist ein Steam-Restart-Artefakt (echt ist steamapps/libraryfolders.vdf) – keine Dangling-Reparatur nötig.

**Rollback-Kommando:** nicht nötig; bei Bedarf nur `sudo snap install --classic steam` (würde allerdings zwei Steam-Installationen erzeugen – nicht empfohlen).

### R4 – virtualbox-7.2 Oracle-Repo | Severity: MEDIUM (Doku-Lücke, nicht Paketzustand)

**Verifiziert installiert:** `virtualbox-7.2 7.2.20-175154~Ubuntu~noble`; Module geladen (vboxdrv refcnt=4, kein VB-VM-Prozess); udev-Regel `/etc/udev/rules.d/60-vboxdrv.rules` vorhanden; Override `/etc/systemd/system/vboxdrv.service.d/60-group.conf` Inhalt: `ExecStartPost=/bin/sh -c "chgrp vboxusers /dev/vboxdrv …"` (Oracle-Init überschreibt udev – Doku stimmt). Repo: `/etc/apt/sources.list.d/virtualbox.list`, Key `/usr/share/keyrings/oracle-virtualbox-2016.gpg`. User in `vboxusers`.

**Rückbau-Anleitung in der Doku: unvollständig.** Die Doku listet die Komponenten, nennt aber keine Kommandos, und ein kritischer Fakt fehlt: `dpkg -S /etc/udev/rules.d/60-vboxdrv.rules` → **nicht paketgeführt** (selbst angelegt). Ein `apt purge virtualbox-7.2` entfernt also **weder** die Udev-Regel **noch** den systemd-Override **noch** Repo/Key **noch** die Gruppe. Ohne manuellen Schritt bleiben Regel+Override mit verwaisten Device-Rechten zurück.

**Rollback-Kommando (vollständig):**
`sudo apt purge virtualbox-7.2 && sudo rm /etc/udev/rules.d/60-vboxdrv.rules /etc/apt/sources.list.d/virtualbox.list && sudo rm -rf /etc/systemd/system/vboxdrv.service.d && sudo systemctl daemon-reload && sudo udevadm control --reload && sudo deluser z000g9hu vboxusers && sudo groupdel vboxusers && sudo rm /usr/share/keyrings/oracle-virtualbox-2016.gpg`
(+ VM-Daten `~/VirtualBox VMs/` separat löschen; Doku sollte diese Zeile ergänzen.)

### R5 – KVM-State-Korruption: Evidenz für „Reboot als einziger Fix“ | Severity: HIGH (blockiert, aber sicherheitsneutral für Daten)

**Belegte Evidenzkette (heute direkt am Host erhoben):**
1. `dmesg` (Zeitstempel ~40823 s ≈ 23:5x, deckt sich mit Doku-Uhrzeit): Burst `vmwrite_error: 153 callbacks suppressed`, danach >10 sichtbar `kvm_intel: vmwrite failed: field=… err=0` **und** `kvmread/vmread failed: field=4400` – VMCS-Validity ist im Modul weg, Hardware meldet während VM-entry.
2. Kein QEMU/VBox-Prozess läuft (`ps` leer), `fuser -v /dev/kvm` → **keine** Halter-Dateideskriptoren.
3. `lsmod`: `kvm_intel 540672 2` → Referenzzähler 2 ohne Nutzer = **Refcount-Leak** (Kombination Triple-Fault + `kill -9` auf qemu beim kvm-venus-Versuch).
4. `sudo rmmod kvm_intel` → `ERROR: Module kvm_intel is in use` – Reload-Pfad damit ausgeschlossen, solange kein /dev/kvm-Holder existiert: der Zähler lässt sich aus Userspace nicht auf 0 bringen.
→ Damit ist ein Neuladen des Moduls ohne Reboot unmöglich; **Reboot ist der einzige verbleibende Fix** (alternativ Kernel-Patch/Upgrade, längerfristig). Datenrisiko des Reboots: keines der nächtlichen Artefakte hängt im RAM – Snapshot, GRUB-Stage, Steam-Daten sind alle disk-persistiert geprüft (R1–R3).

**Rollback-Kommando:** keins nötig; Verifikation nach Reboot: `dmesg | grep -iE 'vmwrite|invalid vmcs'` (leer), `virsh start kvm-siemens`, `cat /proc/cmdline | grep -o 'iommu=pt'`.

## Gesamturteil

Alle fünf Änderungen sind **rückholbar**; kein Zustand erfordert sofortiges Eingreifen. Vor dem geplanten Reboot: R4-Doku um die Purge-Kommandos ergänzen; R1 vor längerem Laufzeitbetrieb auflösen (Revert *oder* `--metadata`-Löschung nach Gutheißung), damit das Overlay nicht zum stillen Alleingänger wird.

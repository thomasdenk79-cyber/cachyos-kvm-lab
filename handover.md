# Handover VM-Lab – STAND VOR HOST-RESTART (2026-10-03 ~08:10)

## Vorrang: WSL-Sicherung 2026-10-06

Dieses Repo war vor der Migrationsrunde sauber und bereits auf `origin/main`
gesichert (`7d5097e`). Es wird samt neuem Uebergabehinweis erhalten, nicht
ausgefuehrt. Alle folgenden VM-Zustaende und Rebuild-Schritte sind historische
Aufzeichnungen; keine aktuelle Pruefung/Erlaubnis fuer VM-Neuaufbau auf WSL.
VM-Disks und ISOs werden nicht als Git-Daten gesichert. Die zentrale
Hostuebergabe steht in `llm-infra-setup`, Branch `turbo-c6-production`,
`docs/WSL-MIGRATION.md`; `howto.md` liegt im lokalen privaten Migrations-ZIP.

## Kernbotschaft
Nichts im VM-Status ist jetzigen Wert: alle drei qcow2-Disks ~7 MB (kein Installer
hat substantiell geschrieben). Host-Neustart/Jellyfin-Pause kostet NULL. Danach
einfach `scripts/lab/rebuild-all.sh` (baut Seeds/Doms/Watcher komplett neu).

## Was bereits FEST und committed ist (8f60e55 + diese Datei)
- Infra: zpcachyossrv geupgradet (zstd, bootfrei), Datasets /srv/vms/{disks,iso,seed},
  libvirt-Netz default + feste Leases (.51/.52/.53), Pakete durch.
- Alle 5 ISOs sha256-verifiziert in /srv/vms/iso; Kernel/Initrd-Extrakte in /srv/vms/work/boot.
- Skript-Suite scripts/lab/ (siehe comments dort) inkl. rebuild-all.sh-Kaltstart.
- memory.md Fakten, docs/vm-lab.md Zeiger, dieses Handover, AGENTS.md Fortsetzungsteil.

## Offene Baustellen beim letzten Check
1. vm-win11 (wichtigster Offener): letzter Standard-Lauf (virt-install --cdrom --wait -1,
   Log /srv/vms/work/win-install.log) brachte ohne TTY mit
   "Kann interaktive Konsole ... nicht" ab → nächster Fix: `</dev/null` reichte nicht,
   zusätzlich `setsid`+`--noautoconsole` kombinieren ODER expect-Wrap. Danach
   prüfen, ob 26300-ISO im OVMF überhaupt bootet (war total schwarz, send-key half nicht;
   Verdacht: ISO defekt oder bootmgr ohne Anzeige im headless VGA). Testpfad:
   kurz `--graphics vga --connect` weglassen + screenshot-PNG-Analyse (libvirt schreibt PNG).
2. vm-ubuntu: Subiquity-UI lief sichtbar (lila/83k Farben) aber CPU ~idle & Disk 0 →
   vermutlich wartende Error-Page: storage-Konfig wahrscheinlich falsch
   (esp-flag: 'boot'→'esp' pruefen; bios_grub nicht noetig bei uefi; vendor:Feld entfernen).
   Fix in 10-seed-ubuntu.sh, Seed neu bauen, rebuild.
3. vm-cachyos: SeaBIOS+Direktboot live (CPU 420 busy) – Konsolenlogin war unklar
   (`login:` root ohne PW, User 'liveuser'); 31-drive-cachyos.exp bei Bedarf an
   'liveuser' + sudo anpassen. cachyos-live.sh nutzt jetzt GRUB i386-pc (kein bootctl).
4. Remmina protocol=4 (RDP) noch NICHT verifiziert; Fallback .desktop da.
5. 50-connect.sh noch nie gelaufen.

## Fortsetzungsreihenfolge nach Neustart (exakt)
1. `sudo zpool import zpcachyossrv` (falls nicht auto), `ls /srv/vms/iso` OK?
2. LLM/Host stabil -> `cd ~/work/cachyos-kvm-lab/scripts/lab && ./rebuild-all.sh`
3. Ubuntu-Fix vorab einbauen (esp-flag, vendor-Feld weg) – siehe Baustelle 2.
4. Win: Screenshot-PNG-Methode aus diesem Repo (python-pillow installiert) nutzen;
   falls ISO stinkt -> offizielle 24H2/25H2 Eval-ISO per Browser-Nachhilfe vom User.
5. cache: VM-Ergebnisse in docs/vm-lab.md dokumentieren, committen, pushen.

## Fallstricke (unveraenderlich, auch in memory.md)
- pkill -f selbsttoetend ([B]rackets!), Dataset-MountS VOR Downloads,
  undefine --remove-all-storage loescht ISOs!, virt-install 5: --install kernel=
  unvertraeglich mit --cdrom; --boot bios existiert nicht; isa-serial->serial; std->vga;
  OS-boot vs per-device boot mutually exclusive; Python 3.14 ohne crypt.
- Remmina/xfreerdp nutzen pw aus creds.env – nie ins Repo.

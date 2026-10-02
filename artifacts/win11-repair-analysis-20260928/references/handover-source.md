# Arbeitsübergabe

## Win11-Reparaturdiagnose 2026-09-28

- Keine Neuinstallation ausgeführt. `win11-siemens` wurde für Tests gestoppt
  und bleibt ausgeschaltet; `win11-hpzbook` blieb unangetastet.
- ZFS-Snapshot `zpcachyos/vms/win11@pre-secureboot-off-test-20260928` schützt
  den aktuellen Zustand. ZFS und `domblkerror` melden keine Fehler.
- Secure Boot testweise deaktiviert und anschließend wieder aktiviert; die
  automatische Reparatur tritt in beiden Varianten auf. Secure Boot ist nicht
  die Ursache.
- Offline-Logs aus dem ZVOL zeigen den eigentlichen Fehler: Windows Setup
  installiert während OOBE KB5128942/CloudExperienceHost-Komponenten, fordert
  einen Neustart und scheitert danach beim BFSVC-Kopiervorgang von
  `G:\$WINDOWS.~BT\Sources\Boot\EFI_EX\bootmgfw_EX.efi` mit `0x3`; danach
  scheitert der BCD-Systemstore mit `c000000f`. Die Srt-Diagnose findet keine
  Datenträger- oder Dateisystemkorruption.
- Zusätzlich wurde die Domain für den Test auf ZVOL-Boot 1 ohne Installations-
  CDs gestellt; auch damit bleibt die Reparatur bestehen. Der Fehler liegt im
  Windows-OOBE/Servicing-Boot-Handoff, nicht in der QEMU-Bootreihenfolge.

## Win11-Siemens Fresh-Install 2026-09-27 22:02 CEST

- Nur `win11-siemens` wurde neu aufgebaut; `win11-hpzbook` blieb unangetastet,
  damit der physische Ethernet-Port nicht vom Host getrennt wird.
- `scripts/win11-zvol-vm.sh --apply --no-install --fresh-install --force`
  lief mit der bereits gestagten Windows-ISO erfolgreich durch. Die VM läuft
  jetzt mit stabiler UUID/SMBIOS-Seriennummer/MAC, 16 GiB RAM, 4 vCPUs,
  Secure-Boot-OVMF, TPM 2.0, SATA-ZVOL, e1000e-Netzwerk und 200-GiB-ZVOL.
- Die Bildschirmprüfung zeigt den Windows-Installer bei 16 %; der Gast setzt
  die Neuinstallation selbstständig fort.
- Behobene Skriptfehler: staged ISO wird bei nicht gemountetem Wechselmedium
  wiederverwendet; OVMF-Code/NVRAM wird explizit gesetzt; Fresh-Dry-Run hängt
  nicht mehr; die Prüfung liest Secure-Boot-Key enrollment aus dem NVRAM.
  Libvirt fügt auf diesem Host trotz `--watchdog none` einen Plattform-
  Watchdog ein; die Prüfung akzeptiert diesen Host-Default, Ballooning bleibt
  deaktiviert.
- Prüfungen: `bash -n`, `git diff --check`, Dry-Run Exit 0, `--check` Exit 0,
  `virsh` Domain running, `zpool status -x` gesund.

## Win11-Passthrough-Stand 2026-09-27

- Host-Port verifiziert: `enp0s31f6`, MAC `7c:4d:8f:2b:a8:ee`, PCI-BDF
  `0000:00:1f.6`, Intel e1000e. WLAN `wlan0` ist aktuell verbunden; der
  neue Code nimmt den Fallback dynamisch aus NetworkManager statt den Namen
  fest zu codieren.
- `win11-hpzbook` ist mit 4 vCPUs, 16 GiB, neuem ZVOL `zpcachyos/vms/win11-hpzbook`,
  `zstd-1`, `cache=writethrough`, `io=io_uring`, SATA, Secure Boot/TPM und
  eigenem OVMF-NVRAM definiert. Der Start ist derzeit sicher blockiert, weil
  der Host noch ohne IOMMU gebootet wurde; der Ethernet-Port bleibt aktiv.
- `scripts/win11-enable-iommu.sh` ergänzt auf Intel `intel_iommu=on iommu=pt`
  (auf AMD automatisch `amd_iommu=on iommu=pt`), VFIO-Module und BLS-
  Kernelparameter. Ausführung verändert Boot/initramfs und erfordert danach
  einen Neustart. `scripts/win11-pci-passthrough-undo.sh` bleibt als manueller
  Rückweg verfügbar.
- Der Shared-Setup-Code prüft vor dem Trennen des Ports verbundene Host-
  Fallback-Netze und aktive IOMMU-Gruppen. Wenn `virsh start` scheitert, wird
  der Port sofort wieder angehängt; nach normalem VM-Halt erledigt das der
  Lifecycle-Watcher.
- Nächster sicherer Schritt: laufende Siemens-VM sauber beenden, IOMMU-Skript
  ausführen, Host neu starten und danach `win11-hpzbook --apply --no-install
  --fresh-install --force` erneut ausführen. Erst dann darf der physische Port
  an die zweite VM gehen.
- Git: Implementierung in `57eacad`, Restore-Berechtigung in `2909e70`; beide
  Commits sind nach `origin/main` gepusht. Fremde unversionierte Dateien
  (`artifacts/`, `scripts/libvirt-vm-backup.sh`, `setup_zfs.sh`) bleiben bewusst
  unangetastet.

## Win11-Zwei-Phasen-Setup 2026-09-27

- Phase 1 wurde konservativ korrigiert: 16 GiB, 1 Socket/4 Cores,
  `host-passthrough` mit `migratable=off`, SATA/raw-ZVOL,
  `cache=none`, `io=io_uring`, `discard=unmap`, standardmäßig keine
  Hugepages, kein Ballooning und kein Watchdog. Secure-Boot-Firmware meldet
  jetzt explizit `secure-boot=yes` und `enrolled-keys=yes`; der per-VM-NVRAM-
  Store wird weiterhin mit Microsoft-2011/2023-Keys bestückt.
- Hyper-V-Enlightenments werden aus der vorhandenen Definition übernommen und
  je Feature mit einem lokalen QEMU/KVM-Probe geprüft; nicht unterstützte
  Features werden entfernt. Ein optionaler `WIN11_NETWORK_LINK_STATE=down`
  bleibt für Offline-OOBE verfügbar, ist aber nicht Standard.
- Phase 2 liegt in `scripts/win11-phase2-tune.sh`. Sie ist read-only prüfbar
  und verlangt für Änderungen `WIN11_PHASE2_STABLE_BOOT_CONFIRM=YES`; sie
  schaltet nach installierten VirtIO-Treibern auf VirtIO-SCSI und virtio-net/
  vhost (bei Passthrough bleibt das Hostgerät), entfernt Installationsmedien,
  setzt die Systemdisk an Bootposition 1 und fügt den QEMU-Guest-Agent-Kanal
  hinzu.
- Die geänderten Skripte sind syntaktisch geprüft. Keine VM wurde für diese
  Phase-1/Phase-2-Änderung neu erzeugt oder rebootet; das erfolgt nach dem
  geplanten Hostneustart kontrolliert.

## Win11-Fresh-Setup-Zielzustand 2026-09-27

- OOBE-Netzwerk-Link-Workaround vollständig zurückgenommen; der Gast startet
  wieder mit normal aktivem e1000e-Netzwerk.
- `--fresh-install --force` erzeugt ZVOL, Domain und per-VM-NVRAM neu. Aus dem
  OVMF-VARS-Template werden vor dem ersten Boot Microsoft-PK/KEK/db-Schlüssel
  2011/2023 mit `virt-fw-vars` enrolliert.
- Automatische Prüfung meldet Q35/KVM, 16 GiB, host-passthrough, Secure Boot,
  PK/KEK/db, TPM `tpm-crb`, SATA-Disk, cache=none/io_uring/discard=unmap,
  e1000e-Netzwerk, feste UUID/Seriennummer/MAC.
- Verifizierter Fresh-Lauf mit Exit 0: neuer NVRAM-Store angelegt, Schlüssel
  vor VM-Start enrolliert, VM gestartet. Der Windows-Installationsfortschritt
  bleibt der nächste Gasttest.

## Win11 Secure-Boot- und Paketkorrektur 2026-09-27

- Paketabgleich abgeschlossen: QEMU/libvirt/OVMF/swtpm/SPICE/Netzwerk- und
  RDP-Werkzeuge sind installiert. `qemu-tools` existiert unter Arch/CachyOS
  nicht; `qemu-system-x86`, `qemu-img` und `qemu-base` liefern dessen Inhalte.
  `virt-firmware`/`virt-fw-vars` wurde nachinstalliert und in die Skript-
  Abhängigkeiten aufgenommen.
- Der ursprüngliche per-VM-NVRAM enthielt keine PK-, KEK- oder db-Variablen,
  obwohl Secure Boot im XML aktiv war. Microsoft-PK/KEK/db für 2011 und 2023
  wurden testweise mit `virt-fw-vars --enroll-microsoft` eingetragen.
- Das Skript enrolliert den Schlüsselbestand nun idempotent und verwendet bei
  (historischer Zwischenstand; der aktuelle Fresh-Pfad erzeugt den NVRAM neu)
  und enrolliert die Schlüssel vor dem ersten Boot.
- Der manuelle Secure-Boot-Test zeigte zunächst nur den erwarteten CD-
  Wartebildschirm; der Skriptpfad sendet `Enter` automatisch. Die VM bleibt bis
  zum nächsten vollständigen Testlauf ausgeschaltet.

## AGENTS-Arbeitsprofil 2026-09-27

- Coding-, Parallelagenten-, Checkpoint-, Push- und Compaction-Regeln stehen
  jetzt direkt in `AGENTS.md`; die doppelte Prompt-Datei unter `docs/` wurde
  entfernt.
- `README.md` verweist auf `AGENTS.md` als zentrale Quelle.
- Die bestehende unversionierte `artifacts/`-Datei sowie andere fremde
  Arbeitsbaumänderungen wurden nicht angefasst.

## ShellCheck-/Konsole-Dokumentation 2026-09-27

- `setup_cachyos.sh` installiert künftig zusätzlich `shellcheck` und `konsole`.
- `README.md` erklärt Konsole als KDE-Terminal, die automatische Installation
  der Laufzeitabhängigkeiten und den Zweck von ShellCheck.
- Commit `a339abb` wurde ohne Force nach `origin/main` gepusht.
- Die bereits vorhandenen unversionierten Dateien `scripts/libvirt-vm-backup.sh`
  und `setup_zfs.sh` wurden nicht angefasst.

## KDE-Arbeitsfläche 2026-09-27 15:35 CEST

- Desktop jetzt schwarz und ohne sichtbare Symbole: Plasma-Containments 44/45
  auf `org.kde.color` mit `Color=0,0,0` gesetzt und auf das leere Verzeichnis
  `~/.local/share/empty-desktop` verwiesen. Vorhandene Desktop-Dateien bleiben
  im echten Desktop-Verzeichnis erhalten.
- Taskleiste/Panel auf automatisches Ausblenden (`hiding=1`) gesetzt.
- `plasmashell --replace` erfolgreich gestartet; Energieverwaltung wurde nicht
  geändert. README um reproduzierbare Kommandos ergänzt.

## KDE-Konfigurationskorrektur 2026-09-27 15:45 CEST

- Die erste Variante mit leerem Folder-View und `hiding=1` wurde zurückgerollt:
  sie entfernte das Desktop-Kontextmenü und machte das Panel unerreichbar.
- Aktueller stabiler Zustand: Panel sichtbar (`hiding=0`), beide Desktop-
  Containments wieder `desktop:/`, schwarze Wallpaper bleiben aktiv. Plasma
  wurde neu geladen; Rechtsklick/Kontextmenü ist damit wieder verfügbar.
- README beschreibt nur noch die sichere Schwarz-Konfiguration.

## KDE-Meta-Taste 2026-09-27 15:50 CEST

- Ursache für die scheinbar wirkungslose Windows-Taste war die Kickoff-
  Applet-Zuordnung `global=Alt+F1`. Sie ist jetzt auf `global=Meta` gesetzt;
  Plasma wurde neu geladen. Die KWin-Fensterübersicht bleibt `Meta+W`.

## KDE-Meta-Korrektur 2026-09-27 15:55 CEST

- Benutzerpräferenz präzisiert: Meta allein soll die Fensterübersicht mit
  Miniaturen öffnen; Kickoff bleibt auf `Alt+F1`.
- `kglobalshortcutsrc` auf `Overview=Meta,Meta,...` und Kickoff auf
  `global=Alt+F1` gesetzt. Der laufende Global-Shortcut-Dienst bietet keine
  Reload-Methode; Ab-/Anmeldung ist der sichere Aktivierungspunkt.

## Plasma-Dienst wiederhergestellt 2026-09-27 20:43 CEST

- `plasmashell --replace` hatte den systemd-verwalteten Plasma-Prozess beendet;
  deshalb fehlten Panel und Desktop-Kontextmenü trotz korrekter Konfiguration.
- Mit `systemctl --user start plasma-plasmashell.service` erfolgreich
  wiederhergestellt; Dienst ist aktiv und `plasmashell --no-respawn` läuft.
- README korrigiert: künftig `systemctl --user restart
  plasma-plasmashell.service` verwenden.

## Win11-KVM-Neuaufbau 2026-09-27 16:20 CEST

- EFI-Forensik am ZFS-Klon geprüft: `/dev/zd16p1` (100-MiB-ESP) hatte 34 MiB
  belegt und 63 MiB frei (36 %). Bootmanager, `bootmgfw.efi`, `bootmgr.efi`
  und BCD-Dateien waren vorhanden; kein EFI-Platzmangel.
- Panther-Logs bestätigt: Windows-OOBE installierte ein ZDP-/LCU-Update,
  `CloudExperienceHost` war noch in Benutzung und verlangte danach einen
  Neustart. FirstLogon-Update-/Winget-Aktionen wurden aus dem Postinstall-
  Skript entfernt; die ESP-Größe im Autoattend auf 260 MiB erhöht.
- Fresh-Lauf zunächst an einem abhängigen Forensik-Klon/Snapshot abgebrochen.
  `--fresh-install --force` entfernt solche abhängigen ZFS-Klone/Snapshots nun
  kontrolliert, inklusive Partition-Mounts; normale Läufe behalten sie.
- `WIN11_HUGEPAGES=0` war vorher wirkungslos, weil `USE_HUGEPAGES` fest auf 1
  stand. Das Skript deaktiviert Hugepages jetzt bei Wert 0 korrekt.
- Testlauf erfolgreich: `WIN11_REFRESH_MEDIA=0 WIN11_HUGEPAGES=0
  WIN11_START_VM=1 scripts/win11-zvol-vm.sh --apply --no-install
  --fresh-install --force` beendete sich mit Exit 0. Domain `win11-siemens`
  läuft, ZVOL `zpcachyos/vms/win11` ist eingebunden, EFI/OVMF und TPM sind
  definiert. Der aktuelle Lauf wartet nun auf den eigentlichen Windows-
  Installationsfortschritt/OOBE.
- Offene Prüfung: Nach der Windows-Installation den dritten Neustart und die
  Siemens-/Intune-Anmeldung beobachten; erst danach Updates und Winget wieder
  freigeben. Keine Zugangsdaten oder Unternehmenslogs dokumentiert.
- Git: Änderungen in Commit `afc41f9` festgehalten und ohne Force nach
  `origin/main` gepusht. Lokale unversionierte Dateien `scripts/libvirt-vm-backup.sh`
  und `setup_zfs.sh` gehören nicht zu diesem Meilenstein.

## OOBE-Netzwerk- und Recherchepaket 2026-09-27 20:50 CEST

- Der nächste Lauf bestätigte erneut den Fehlerablauf in den Windows-Logs:
  OOBE-ZDP lädt ein Update, installiert es, fordert einen Neustart an und
  BFSVC meldet danach den temporären `bootmgfw.efi`-/BCD-Fehler. EFI war dabei
  nur zu etwa 14 % belegt; ZFS und QEMU blieben fehlerfrei.
- Microsofts OOBE-Dokumentation beschreibt ZDP als automatischen, nach
  Netzwerkverbindung ausgelösten Updatepfad. Der zwischenzeitliche
  Link-State-Workaround wurde danach vollständig zurückgenommen; der aktuelle
  Setup-Pfad startet mit normal aktivem Netzwerk.
- Der erste Versuch dieser Änderung hatte den Link wegen fehlender
  Umgebungsübergabe noch auf `up`; die Übergabe an den XML-Postprozessor ist
  korrigiert. Aktueller Testlauf läuft mit `vnet27 down`.
- Browser-Agent-Paket erstellt:
  `artifacts/win11-browser-analysis-20260927.zip` (SHA256
  `34e23f29c91a21415095f8de2c1be6c0ee0538cc65b6e6f7fa00b472a33d71bf`). Es
  enthält Skript, Support-ISO-Dateien, Domain-XML, Hostlogs, Fehlerauszüge und
  Rechercheprompt; keine Zugangsdaten.

## KDE-Sperrbildschirm 2026-09-27 15:20 CEST

- Plasma 6-Konfiguration gesetzt und verifiziert: `~/.config/kscreenlockerrc`
  mit `Daemon/Timeout=240`, `Daemon/Lock=true`, `Daemon/LockGrace=0`,
  `Greeter/WallpaperPlugin=org.kde.color` und `Color=0,0,0`.
- Die D-Bus-Neukonfiguration wird von dieser Sitzung mit `NotSupported`
  abgewiesen; die Werte greifen spätestens nach Ab-/Anmeldung. Keine
  Repository-Geheimnisse oder systemweiten Änderungen betroffen.

## Storage-/Sysbench-Prüfung 2026-09-27 12:55 CEST

- Sequentieller 1MiB-fio-Test auf dem ZFS-Pool (`iodepth=32`, 16GiB Datei,
  `sync=disabled`, `primarycache=none`) erreichte 847 MiB/s Write und
  845 MiB/s Read.
- Ursache verifiziert: `nvme0` (990 PRO `S7DNNJ0X247235D`) linkt PCIe 3.0 x4,
  `nvme1` (990 PRO `S7DNNJ0X131552B`) linkt PCIe 3.0 x1. Der Pool enthält
  beide Geräte; der x1-Link erklärt die ~0,85 GiB/s. Keine Datenträgeränderung.
- `sysbench fileio` (4K rndrw, 4GiB, direct, 1 Thread) ergab 292,46 MiB/s
  Read und 194,97 MiB/s Write; das ist kein Vergleich zur 7.000-MB/s-Angabe.

## PCIe-Befund dokumentiert 2026-09-27 13:00 CEST

- Anwender bestätigt: Samsung-SSDs in den Haupt-M.2-Slots, Kioxia-SSDs in den
  Nebenslots. Der x1-Link von `nvme1` ist deshalb noch nicht als normales
  Lane-Sharing erklärt.
- Schraubbefestigung schließt Bewegung aus, bestätigt aber weder elektrische
  Kontaktqualität noch erfolgreiche PCIe-x4-Aushandlung. Vor einem Öffnen sind
  Kaltstart, BIOS-/Firmwareprüfung sowie `lspci -vv`/`dmesg` auf Link-Training
  und AER-Fehler auszuführen.
- Kein Umstecken, kein BIOS-Schreibvorgang und keine Pool-/Datenträgeränderung
  durchgeführt. Dokumentationsänderung wird separat committed und gepusht.

## PCIe-Logprüfung 2026-09-27 15:10 CEST

- `lspci -vv` zeigt für Endpoint `03:00.0` (nvme1): `LnkCap Speed 16GT/s,
  Width x4`, aber `LnkSta Speed 8GT/s (downgraded), Width x1 (downgraded)`.
- Der zugehörige Root-Port `00:1b.4` kann ebenfalls x4 (`LnkCap Width x4`),
  handelt aktuell aber selbst nur x1 aus (`LnkSta Width x1`). Damit ist die
  Reduzierung bereits auf der Root-Port-Verbindung sichtbar.
- Im aktuellen Kernel-Bootlog gibt es keine passenden AER-, Link-Training-
  oder Bandwidth-Fehler. Endpoint meldet Capability-Statusbits `CorrErr+`
  und `UnsupReq+`, die AER-Status-/Headerlogs sind jedoch leer; kein Beleg für
  einen konkreten Laufzeitfehler.
- Ergebnis: Linux kann die Ursache nicht weiter auflösen; wahrscheinlich
  Slot-/Board-Verdrahtung, BIOS-Lane-Konfiguration oder Link-Training beim
  Kaltstart. Nächste nicht-invasive Schritte bleiben Kaltstart sowie BIOS-
  und Firmwareprüfung, danach erst ein physischer Slottausch.

## Monitoring-Dashboards 2026-09-27 11:40 CEST

- `scripts/setup_monitoring_podman.sh` erweitert: Grafana setzt lokal den
  Zugang `admin/admin`; `--task=5` aktualisiert Dashboards und setzt das
  Passwort nach einem vorhandenen Datenbanklauf zuverlässig zurück.
- Übersicht um CPU-Auslastung je Kern, Load Average, RAM/Cache, Swap,
  Dateisystembelegung, Datenträgerdurchsatz und IOPS, Netzwerkdurchsatz sowie
  GPU-Auslastung, Temperatur und Leistung erweitert. Byte-/Bit-Raten werden
  über Grafana-Einheiten automatisch als B/s, KiB/s, MiB/s usw. angezeigt.
- Zusätzliches Dashboard `Workstation – Container` für CPU, RAM, Netzwerk,
  Container-I/O und Scrape-Zustand provisioniert.
- Verifiziert: Grafana Health ok, Login mit `admin/admin` ok, beide Dashboards
  sichtbar, Prometheus-Ziele `containers`, `gpu`, `node`, `prometheus` jeweils
  `up`. Passwort selbst wird nicht in dieses Handover geschrieben.
- Arbeitsbaum enthält daneben die bereits vorhandenen, nicht zugehörigen
  Änderungen an `benchmarkbericht.md`, `scripts/win11-zvol-vm.sh`,
  `scripts/zfs-fio-benchmark.sh` und `setup_zfs.sh`; diese wurden nicht
  gestaged.

## Hardware-Sensoren und Storage-Dashboards 2026-09-27 12:25 CEST

- Sensorpipeline ergänzt: `lm_sensors` wird alle 15 Sekunden über einen
  node-exporter-Textfile-Collector eingesammelt. Auf diesem Host erscheinen
  CPU/Core-, drei NVMe-Geräte, PCH, ACPI und WLAN-Temperaturen sowie verfügbare
  Batterie-Spannung/Stromwerte.
- `smartctl_exporter` läuft rootful und liefert nun für `nvme0` bis `nvme3`
  SMART/NVMe-Temperatur, Percentage Used und Bytes Written. Der Prometheus-Job
  `smartctl` ist `up`; ZFS-Metriken kommen aus dem aktivierten node-exporter-
  Collector `zfs`.
- Neue Dashboards: `Workstation – Storage & Sensoren` mit getrennten
  Lesen/Schreiben-MB/s- und IOPS-Panels sowie `Workstation – Temperaturen &
  Leistung`.
- Verifiziert: fünf Grafana-Dashboards sichtbar, Login `admin/admin`, Jobs
  `containers`, `gpu`, `node`, `prometheus`, `smartctl` jeweils `up`.
- Die erste Prüfung sah `/sys/class/powercap` ohne Root-Rechte leer. Nach
  Root-Prüfung und `intel_rapl_msr`-Modul sind Package, Core, Uncore, DRAM und
  `psys` vorhanden. Der Textfile-Exporter berechnet daraus Watt über
  Energie-Deltas; verifiziert wurden Werte für alle fünf Domains.
- Neue Ansicht `Workstation – CPU & Platform Power` zeigt diese RAPL-Werte.
  Eine separate iGPU- oder SSD-Wattmessung liefert die Plattform nicht; die
  Package-/Platform-Werte bleiben die vom Kernel tatsächlich bereitgestellten
  Domains, während GPU-Watt weiterhin aus DCGM kommt.

## GPU-Tools 2026-09-27 12:40 CEST

- `nvtop` und `intel-gpu-tools` installiert und in den Monitoring-
  Abhängigkeiten ergänzt. `nvtop -s` erkennt Quadro T2000 und Intel UHD;
  `intel_gpu_top` zeigt die Intel-GPU-Engine-Last und Package-Power.
- Live-Prüfung: NVIDIA etwa 20–21 W; Intel-GPU-Engine etwa 0–1 % bei
  1150 MHz. Zed ist im `nvtop` der Intel-GPU zugeordnet.

## Berichtskorrektur 2026-09-27 11:40 CEST

- Der Benchmarkbericht wurde korrigiert: getrennte Read-/Write-IOPS,
  Read-/Write-MiB/s und Latenzen, ganzzahlige IOPS sowie dokumentierte
  Profileinstellungen.
- Die frühere `1.00x`-Darstellung war nur für den fio-Zufallsbuffer gültig;
  sie wurde nicht mehr als allgemeine Kompressionsaussage verwendet.
- Neuer reproduzierbarer RAM-basierter Vergleich in
  `benchmarkbericht-kompression.md`: 1 GiB `/dev/urandom` und 202 MiB
  Silesia-Mischkorpus, je `off`, `lz4`, `zstd-1/2/3/10/19`, Write/Read und
  ZFS-Compressratio. Silesia zeigt z. B. zstd-3 2,79x und zstd-19 3,14x;
  Zufallsdaten bleiben bei 1,00x.
- Neues Skript: `scripts/zfs-corpus-compression-benchmark.sh`; Lauf erfolgreich,
  temporäre Datasets entfernt. Commit `f5c0470` nach `origin/main` gepusht.

## Benchmarkprüfung 2026-09-27 11:20 CEST

- `scripts/zfs-fio-benchmark.sh` gehärtet: alle 84 Eigenschaftskombinationen
  und drei Profile werden trotz einzelner Fehler weiter abgearbeitet; Fehler
  werden pro Kombination protokolliert und am Ende mit Exit-Status 1 gemeldet.
- SLC-Cache-Modus ergänzt: geschätzte Schreibbytes aus fio-JSON, Pause ab
  80 % eines konfigurierbaren Cachewerts (Standard 400G), Dokumentation im
  Report. Der Samsung-990-PRO-SMART liefert keinen direkten SLC-Füllstand.
- Vollständiger Lauf erfolgreich: Run `20260927-101217`, 252/252 Profile,
  `benchmarkbericht.failures` leer. Empfehlung und Rohdaten stehen in
  `benchmarkbericht.md` und `benchmarkbericht.tsv`.
- Temporäre ZFS-Datasets wurden nach dem Lauf manuell mit `zfs destroy -r -f`
  entfernt; Cleanup im Skript nutzt diesen robusten Pfad künftig automatisch.
- Commits `ca39a5a` und `8b158ec` sind nach `origin/main` gepusht. Offene
  Arbeitsbaumänderungen (`scripts/win11-zvol-vm.sh`, `setup_zfs.sh`) stammen
  aus dem vorherigen Arbeitsstand und wurden nicht angefasst.

## Prüfung 2026-09-27 10:20 CEST

- Ursache für das fehlende `/dev/zfs` geprüft: Kernelmodule `zfs` und `spl`
  sind geladen und aktiv; `/proc/misc` registriert `zfs` als Major 10, Minor
  249. Der Gerätknoten fehlt nur in der eingeschränkten Container-
  Geräteansicht. Die Laufumgebung hat keine Capabilities (`CapEff=0`) und
  `NoNewPrivs=1`, daher kann sie `/dev/zfs` nicht anlegen oder den ZFS-Pool
  abfragen.
- Es wurden keine ZFS-, Pool- oder Datenträgeränderungen vorgenommen. Die
  Prüfung muss in der echten Host-Sitzung mit sichtbarem `/dev/zfs` erfolgen.

## Prüfung 2026-09-27 10:10 CEST

- Einhängen der externen SSD versucht: `udisksctl`, `gio` und ein
  schreibgeschütztes Direkt-Mount wurden von der eingeschränkten Umgebung
  blockiert (`Operation not permitted` bzw. fehlende Superuser-Rechte).
- `/dev/sda1` (Ventoy) und `/dev/sda3` (DATA_NTFS) bleiben unverändert und
  nicht eingehängt; es wurden keine Schreibzugriffe auf die SSD ausgeführt.

## Prüfung 2026-09-27 10:05 CEST

- Anwender hat den vollständigen Win11-ZVOL-Aufbau und die Überwachung
  freigegeben. Ein Apply-Lauf wurde noch nicht gestartet, weil die externe
  Ventoy-/Daten-SSD weiterhin nicht eingehängt ist und keine ISO-Dateien
  sichtbar sind.
- `scripts/win11-zvol-vm.sh` weiter gehärtet: `--check` liefert bei fehlenden
  Werkzeugen, Pool oder Medien nun einen Fehlerstatus; `zpool list` ist mit
  Timeout abgesichert; Medienprüfung läuft vor Hugepages- und ZVOL-Anlage.
  Syntaxprüfung und `git diff --check` erfolgreich.
- Aktueller Check: `virsh`, `virt-install` und `virt-manager` fehlen; der Pool
  ist in dieser eingeschränkten Umgebung nicht abfragbar; Windows- und VirtIO-
  ISO fehlen. Keine VM-, ZVOL-, Paket- oder Dienständerung ausgeführt.
- Commit/Push bleibt offen, da `.git` in der Laufumgebung schreibgeschützt ist
  und der externe Remote hier nicht erreichbar ist.

## Prüfung 2026-09-27 09:55 CEST

- `scripts/win11-zvol-vm.sh` geprüft und die ISO-Erkennung erweitert: explizite
  Pfade haben Vorrang; danach werden Windows-11- und VirtIO-ISOs unter
  eingehängten `/run/media/$USER`, `/media/$USER` und `/mnt`-Pfaden gesucht.
  `bash -n` und `git diff --check` waren erfolgreich.
- `--check` meldet auf dieser eingeschränkten Prüfumgebung fehlende
  `virsh`/`virt-install`/`virt-manager`-Befehle und kann `zpool list` nicht
  erfolgreich abfragen; es wurden keine ZVOL-, Paket- oder VM-Änderungen
  ausgeführt.
- Die externe SSD ist als `/dev/sda1` (exFAT, Label `Ventoy`) und `/dev/sda3`
  (NTFS, Label `DATA_NTFS`) erkannt, aktuell aber nicht eingehängt. Ein
  schreibgeschütztes Mount war wegen der Container-Sudo-Beschränkung nicht
  möglich; ISO-Dateien konnten daher noch nicht direkt verifiziert werden.

## Prüfung 2026-09-27 09:40 CEST

- Arbeitsbaum erneut geprüft: Branch `main`; keine Setup-/Installer-Prozesse und
  keine fehlgeschlagenen systemd-Dienste erkannt. Host ist CachyOS mit KDE,
  Kernel `7.2.8-1-cachyos`.
- Lokaler Stand und Remote sind seit der letzten Notiz auseinander gelaufen;
  `git status` meldete einen unversionierten `setup_zfs.sh`. Es wurde nichts
  automatisch gemergt, verworfen oder gepusht.
- `config/local-machine.env` und der externe Secret-Store waren nicht vorhanden.
  Deshalb wurde kein Setup-Lauf gestartet und keine Installation ausgeführt.

## Prüfung 2026-09-27 (Zstd-Freigabe für Fio-Benchmark)

- `zpcachyos` ist nach der RAID-0-Aufnahme weiterhin `ONLINE`; beide VDEVs sind
  fehlerfrei.
- `feature@zstd_compress` steht auf `enabled`. Ein temporäres Dataset mit
  `compression=zstd-3` wurde erfolgreich erstellt, geprüft und wieder entfernt.
- Produktive Datasets bleiben unverändert (weiterhin `lz4` bzw. geerbte Werte).
- Der Fio-Benchmark kann nun grundsätzlich mit den Zstd-Profilen laufen; noch
  kein Benchmark-Lauf gestartet.
- Letzte Prüfung: 2026-09-27; kein Neustart erforderlich.

## Prüfung 2026-09-27 (Bootmanager und setup_zfs.sh)

- `bootctl status` und `efibootmgr` bestätigen systemd-boot als aktuell
  laufenden und ersten Bootloader (`BootCurrent: 0003`, `Linux Boot Manager`).
- `setup_zfs.sh` und `scripts/setup_zfs.sh` sind bytegleich. Das Skript ist für
  ZFSBootMenu/rEFInd-Bootkonfiguration gedacht, nicht für Pool-Erstellung oder
  Fio-Benchmarks. `--apply` bleibt wegen des unerwünschten rEFInd-Pfads aus.
- ZFS-Pool und Zstd-Feature bleiben unverändert nutzbar; kein Neustart nötig.

## Prüfung 2026-09-27 (systemd-boot, ZFSBootMenu und Windows-Testloader)

- Auf der leeren Kioxia `/dev/nvme3n1` wurde eine GPT-ESP `/dev/nvme3n1p1`
  (1 GiB, FAT32, Label `TEST-EFI`) angelegt.
- GRUB wurde dort ohne rEFInd als `Windows-Test` installiert. Die Konfiguration
  chainloadet die geprüfte Windows-Datei `EFI/Microsoft/Boot/bootmgfw.efi` von
  der separaten Windows-ESP. Firmware-Eintrag `Boot0001` existiert; die
  Standardreihenfolge beginnt weiterhin mit `Boot0003` (Linux Boot Manager).
- Paket `zfsbootmenu` wurde installiert. Die ZBM-Konfiguration nutzt `/boot`
  als ESP, erzeugt `/boot/EFI/ZFSBootMenu/vmlinuz-linux-cachyos.EFI` und ist
  über `zfsbootmenu.conf` im systemd-boot-Menü eingetragen.
- `bootctl list`, ZFS-Pool-Health und Windows-EFI-Datei wurden geprüft. Kein
  Neustart und kein Boot-Test wurden automatisch ausgelöst; ein manueller
  Test über den ZFSBootMenu-Eintrag und danach `Windows Test Chainloader` steht
  noch aus.

Stand: 2026-09-27 04:05 CEST
Branch: `main`
Letzter Remote-Commit vor dieser Arbeitsänderung: `e450936`

## Nachtrag 2026-09-27

- `scripts/install_chatgpt_desktop.sh` ergänzt: installiert das offizielle
  x86_64-RPM aus `~/Downloads` auf CachyOS per `bsdtar`, aktualisiert den
  Desktop-Starter und unterstützt DEB-Dateien, sofern `dpkg` vorhanden ist.
- README um die Verwendung ergänzt. `bash -n`, `--help` und `git diff --check`
  waren erfolgreich.
- Commit `347603d` wurde nach `origin/main` gepusht.
- Die bereits vorhandenen Änderungen an `benchmarkbericht.md` und die
  unversionierte Datei `scripts/win11-zvol-vm.sh` blieben unverändert.

## Aktuelle Arbeitsänderung

- `scripts/win11-zvol-vm.sh` ergänzt/erweitert: konfigurierbarer Win11-
  Hochleistungsaufbau auf `zpcachyos`, festes oder dynamisches 200-GiB-ZVOL,
  zentrale Variablen für Identität, ZFS, I/O, Hugepages, Grafik und ISO-Pfade,
  Paketinstallation, ISO-Download bei fehlenden Dateien, RDP/SPICE-Tuning,
  ACL-Prüfung und automatische `libvirt`/`kvm`-Gruppenmitgliedschaft.
  QEMU/libvirt/virt-manager/SPICE/RDP-Pakete wurden installiert; Dienste laufen.
  Ventoy-ISOs wurden erkannt; die offizielle Windows-Multi-ISO und VirtIO-ISO
  liegen lokal unter `/run/media/z000g9hu/Ventoy/ISO/Imported`.
  `win11-siemens` wurde mit fester UUID/SMBIOS-Serial/MAC definiert; ZVOL und
  Hugepages sind aktiv. Standard bleibt `--check`; `--dry-run`, `bash -n` und
  die XML-/ZFS-Prüfung waren erfolgreich.
- `TODO-WIN11-REBOOT.md` dokumentiert den gesicherten Zustand, Pre-/Post-Reboot-
  Prüfungen und den GRUB-Rückfallweg. Die VM bleibt bis zur Windows-Installation
  ausgeschaltet; ein Host-Neustart wurde nicht vom Agenten ausgelöst.

- `scripts/zfs-fio-benchmark.sh` ergänzt: 84 ZFS-Child-Dataset-Kombinationen
  (compression inklusive zstd-Level 1/2/3/10/19 und lz4, recordsize, sync,
  primarycache) mit OLTP-, KVM- und sequenziellem fio-Profil, JSON-Auswertung,
  `compressratio`, Markdown-Tabelle und Empfehlung.
- `README.md` dokumentiert Aufruf, Dry-Run und Cleanup-Verhalten.
- `bash -n`, `git diff --check` und ein vollständiger Lauf mit lokalen
  zfs/fio-Stubs waren erfolgreich; der echte priorisierte ZFS-Lauf ist unten
  dokumentiert.
- Commit `f8aaff8` wurde nach `origin/main` gepusht; Arbeitsbaum ist sauber.

## Benchmark-Lauf 2026-09-27

- `benchmarkbericht.md` enthält den fortlaufenden Bericht der priorisierten
  lz4-Runde: 45 erfolgreiche Profile mit `sync=standard/disabled`,
  `primarycache=all/none` und den drei Recordsize-Werten.
- Die fünf angeforderten Zstd-Level wurden auf diesem Pool geprüft; alle 15
  getesteten Kombinationen wurden vom Pool mit „pool must be upgraded“
  abgelehnt. Es wurde kein Pool-Upgrade durchgeführt.
- Alle temporären Test-Datasets wurden nach den Läufen entfernt. Rohdaten und
  Fehlerliste bleiben lokal für weitere Läufe erhalten und werden nicht in Git
  versioniert.

## ZFSBootMenu/rEFInd Setup

- `scripts/setup_zfs.sh` ergänzt. Das Skript prüft Pool, EFI-Partition und
  Root-Dataset, setzt `compatibility=openzfs-2.4`, aktiviert Pool-Features,
  setzt bei fehlendem Wert `bootfs`, installiert `zfsbootmenu`/rEFInd und
  erzeugt ZFSBootMenu-Images auf der ESP. GRUB bleibt als Fallback erhalten.
- `sudo ./scripts/setup_zfs.sh --check` und `--plan` liefen erfolgreich.
- Der laufende Pool ist auf `openzfs-2.4` aktualisiert, `bootfs` gesetzt,
  `feature@zstd_compress` aktiviert und alle fünf Zstd-Level wurden mit
  temporären Datasets erfolgreich angenommen. `setup_zfs.sh --apply` ist
  erfolgreich durchgelaufen; rEFInd, Nord-Theme und ZFSBootMenu-Images sind
  vorhanden. Der erste Boot mit rEFInd/ZFSBootMenu steht noch aus.

### Prüfung 2026-09-27 05:42 CEST

- Die 256-GB-Windows-SSD `/dev/nvme2n1` hat keine EFI-Systempartition; sie
  enthält MSR, BitLocker-Datenpartition und zwei Recovery-Partitionen.
- Auf der Linux-ESP `/dev/nvme0n1p1` existiert aktuell kein
  `EFI/Microsoft/Boot/bootmgfw.efi`; ein Windows-NVRAM-Eintrag kann daher nicht
  wiederhergestellt werden, ohne Windows-Recovery/Installationsmedien und den
  BitLocker-Recovery-Key zu verwenden.
- `scripts/setup_zfs.sh --apply` lief erneut erfolgreich. Die manuellen
  rEFInd-Einträge referenzieren jetzt die erkannte ESP-UUID `0191-9516` explizit.
- Der Windows-Datenträger wurde nicht verändert und bleibt bis zur gezielten
  Recovery-Entscheidung unangetastet.

## Abgeschlossen

- `./setup.sh --agent-auto-mode` lief am 23.09.2026 durch; der vollständige
  Verify meldete alle 100 Schritte als bestanden.
- Commit `afbb095` enthält die Setup-Reparaturen, Version `0.2.0` und
  `STATUS.md`; Commit `8aa0955` korrigiert den Puppet-Status. Beide Commits
  wurden nach `origin/main` gepusht.
- Puppet-Prüfung laut `ubuntu.md`: `systemctl` und `journalctl` verwenden. Das
  Siemens-Device-Login war erfolgreich; der Compiler lieferte einen Katalog.
- Der Puppet-Katalog lief bis zum letzten Blick um 07:10 CEST noch. Der Agent
  installierte Siemens-Zertifikatspakete und bereitete TPM2-PKCS#11-Pfade vor.
  Der Benutzer hat ausdrücklich bestätigt, dass der Neustart trotzdem jetzt
  durchgeführt werden soll. Nach dem Boot prüfen, ob Puppet fortgesetzt oder
  abgeschlossen hat und den aktuellen Service-/Journalstatus dokumentieren.

## Offen / nächster sicherer Schritt

- Bei der letzten Prüfung lief `puppet.service` weiterhin aktiv; der
  `puppet agent` hatte den Katalog noch nicht als abgeschlossen gemeldet.
  System-Journal weiter beobachten und erst nach einem Abschlussereignis das
  Ergebnis festhalten. Keine zweite Agent-Ausführung starten, solange der
  aktuelle Lauf aktiv ist. Bei Katalog-/Kerberos-/Hiera-Fehlern keine
  Ignore-Flags verwenden.
- NVIDIA-Paket ist vorhanden, aber der aktive Kernel-Treiber braucht laut
  Setup-Verify Aufmerksamkeit; Neustart wurde nicht ausgelöst.
- Keine mLinux-Test-VM ist definiert. Der Setup-Verify meldete optionale
  OpenVox-/Distrobox-Komponenten als Hinweise.

## Git

Die Wiederaufnahme-Regel in `AGENTS.md` und `memory.md` sowie der Neustand in
dieser Datei sind vor dem Neustart noch zu committen und zu pushen. Vorher
`git diff --check` und Secret-Prüfung ausführen; anschließend Commit-ID und
Push-Status festhalten.

## Prüfung 2026-09-27 (ZFS-Aufnahme zweite Samsung-SSD)

- Git-Stand beim Start: `main`, sauber, gleicher Stand wie `origin/main`; keine laufenden Setup-/Installer-Prozesse.
- Root-Pool `zpcachyos` war vor der Änderung `ONLINE` und bestand aus einem VDEV auf `/dev/nvme0n1p2`; keine Datenfehler.
- Zweite Samsung eindeutig erkannt: `/dev/nvme1n1`, Samsung SSD 990 PRO 2TB, Seriennummer `S7DNNJ0X131552B`, WWN `eui.002538414141a74d`, Größe 1.8T.
- Benutzerentscheidung: RAID 0 / Stripe.
- `zpool add` wurde nach Dry-Run mit der stabilen by-id-Adresse ausgeführt. ZFS legte `/dev/nvme1n1p1` als ZFS-VDEV an.
- Ergebnis: `zpcachyos` ist `ONLINE`, 3.62T groß, beide Top-Level-VDEVs online, keine Datenfehler; kein Resilver erforderlich.
- Letzte Prüfung: 2026-09-27; Neustart nicht erforderlich.
- Dokumentation in Commit `ae8db72` enthalten und nach `origin/main` gepusht; lokaler und Remote-Stand sind synchron.

## Prüfung 2026-09-27 09:52 CEST (externe SSD eingehängt)

- Externe Kingston XS2000 (`/dev/sda`, 3.7T) eindeutig anhand Modell und Seriennummer geprüft.
- `/dev/sda1` (exFAT, Label `Ventoy`) erfolgreich per `udisksctl` unter `/run/media/z000g9hu/Ventoy` eingehängt.
- `/dev/sda3` (NTFS, Label `DATA_NTFS`) konnte der Desktop-Mounter mangels NTFS-Hilfsprogramm nicht einhängen; schreibgeschützter Kernel-`ntfs3`-Mount ist unter `/run/media/z000g9hu/DATA_NTFS` aktiv.
- `/dev/sda2` (`VTOYEFI`) war bereits unter `/run/media/z000g9hu/VTOYEFI` eingehängt. Keine Formatierung, Reparatur oder Schreibzugriffe auf die SSD ausgeführt.
- Zugriff geprüft: Ventoy enthält `ISO`; DATA_NTFS enthält unter anderem `Installers`, `Windows` und `Backups`.

## Prüfung 2026-09-27 10:11 CEST (Win11-ZVOL-VM autonom aufgebaut)

- `scripts/win11-zvol-vm.sh --apply` erfolgreich ausgeführt; benötigte QEMU/libvirt-, UEFI-, TPM-, SPICE- und RDP-Pakete installiert, `libvirtd` aktiviert und Benutzergruppen gesetzt.
- Windows- und VirtIO-ISO wurden wegen exFAT-Zugriffsgrenzen automatisch nach `/var/lib/libvirt/boot` staged; die VM verwendet diese lokalen Kopien.
- Libvirt-Netzwerk `default` wurde aktiviert und auf Autostart gesetzt.
- ZVOL `zpcachyos/vms/win11` (200G, 64K) blieb erhalten; VM `win11-siemens` mit stabiler UUID, SMBIOS-Identität und MAC ist definiert und läuft.
- Hugepage-Reservierung wurde automatisch versucht. Wegen fragmentiertem Host-RAM waren nicht genügend 16-GiB-Hugepages verfügbar; die Teilreservierung wurde freigegeben und die VM ohne verpflichtende Hugepages erfolgreich gestartet.
- Skript gehärtet: idempotente VM-Updates, Medien-Staging, Netzwerk-Autostart, Hugepage-Fallback, QEMU-Seriennummer <=36 Zeichen, Bootreihenfolge ISO vor ZVOL.
- Funktionsprüfung: VM `running`, ZVOL und beide ISO-Laufwerke verbunden, Windows-ISO Bootreihenfolge 1, `--check` erfolgreich. Die Windows-Installation selbst bleibt der interaktive Gastschritt im gestarteten Installer.

## Prüfung 2026-09-27 10:56 CEST (Unattended-ISO und VM-Firewall)

- Win11-Skript erweitert: originale Windows-ISO bleibt Quelle; `xorriso` erzeugt `/var/lib/libvirt/boot/win11-siemens-install.iso` mit `Autounattend.xml`, `vioscsi`, `NetKVM`, QEMU Guest Agent und `Win11-PostInstall.ps1`.
- Lokale Konten werden nur aus einem lokalen Credential-File gelesen; Sonderzeichen im Passwort werden ohne Shell-Evaluation verarbeitet. Microsoft-Konten (`@` im Benutzernamen) werden nicht als lokale Autounattend-Konten verwendet; OOBE/Intune bleibt manuell für MFA.
- Postinstall aktiviert Windows-RDP, startet Windows Update, installiert QEMU Guest Agent sowie optional VS Code und Steam über winget.
- UFW/libvirt-Firewall automatisiert: DHCP/DNS und RDP nur auf `virbr0`, geroutetes NAT von `virbr0` zur erkannten Uplink-Schnittstelle; keine eingehende LAN-zu-Gast-Freigabe.
- Die laufende Siemens-Test-VM war während der ISO-Erstellung im manuellen OOBE und bleibt unverändert; Bildschirmprüfung zeigte die Länder-/Netzwerkabfragen.
- Commit `f3645f1` gepusht.

## Prüfung 2026-09-27 11:44 CEST (vollständiger Reset-/Boot-Test)

- Test-Reset von `win11-siemens` und `zpcachyos/vms/win11` mit `WIN11_RESET_VM=1` durchgeführt; UUID, SMBIOS-Serial und MAC blieben exakt stabil.
- VM enthält originale Windows-ISO, VirtIO-ISO und Support-ISO mit `Autounattend.xml`, NetKVM/vioscsi und Postinstall-Skript.
- UFW/libvirt-Regeln aktiv und begrenzt auf `virbr0` (DHCP/DNS/RDP/NAT).
- Reproduzierbarer Blocker: OVMF meldet nach Reset `No bootable option or device was found`, obwohl die Windows-ISO bitgenau zur Quelle ist und QEMU sie lesen kann. Secure-Boot an/aus ändert den Fehler nicht; daher noch kein Windows-Setup-Durchlauf.
- Skriptänderung in Commit `ba27c1d` gepusht.

## Prüfung 2026-09-27 12:40 CEST (Win11-Setup und Loganalyse)

- Der frühere Reset war ein Testfehler. Die Reset-Logik wurde aus dem normalen
  Skriptlauf entfernt; destruktives Neuaufsetzen ist nur noch mit
  `--fresh-install --force` möglich.
- Die Antwortdatei wählt nun Windows 11 Pro (WIM-Index 6), überspringt die
  Product-Key-Abfrage und enthält VirtIO-Netz-/SCSI-/Stor-Treiber auf der
  Support-ISO. Wegen WinPE-Zuverlässigkeit verwendet der Installationslauf
  standardmäßig SATA; `WIN11_DISK_BUS=scsi` bleibt konfigurierbar.
- Die Windows-Installation lief bis zum ersten Neustart und kopierte Windows
  erfolgreich auf den ZVOL. Der anschließende Setup-Fehler kam aus dem zuvor
  mehrfach unterbrochenen Setup-Zustand; es wurden keine ZFS-Datenfehler
  gefunden.
- Verifiziert: `zpool status -x` meldet ONLINE/no data errors; QEMU-Log enthält
  keine Disk-/ZVOL-I/O-Fehler. Kernel meldete Speicherdruck bei KVM. Hugepages
  konnten nicht vollständig reserviert werden und wurden korrekt auf 0
  zurückgesetzt; 20 GiB sind auf dem aktuellen Hostzustand ungeeignet.
- VM wurde zuletzt mit 12 GiB RAM und ZVOL-Boot (boot order 1) gestartet;
  UUID, SMBIOS-Serial, Disk-Serial, MAC, NVRAM und vTPM-Pfad blieben erhalten.
- Offener Punkt: Für einen wirklich sauberen erneuten Installationslauf ist
  eine ausdrückliche Entscheidung zum Löschen und Neuerstellen des Test-ZVOLs
  erforderlich. Bis dahin keinen Fresh-Install ausführen.

## Prüfung 2026-09-27 13:05 CEST (Fresh-Install erneut gestartet)

- Benutzer hat das erneute Erstellen des Test-ZVOLs ausdrücklich freigegeben.
- `--fresh-install --force` lief mit `WIN11_RAM_MIB=12288` erfolgreich durch:
  VM/ZVOL/NVRAM/vTPM wurden neu erzeugt; UUID, SMBIOS-Serial und MAC blieben
  stabil. Original-ISOs wurden nicht verändert.
- Die VM bootet aktuell von der Original-ISO; Windows-Setup läuft autonom bei
  11 Prozent. Der ZVOL ist während des Installationslaufs SATA-angebunden,
  damit WinPE ohne zusätzliche SCSI-Treiber zuverlässig sichtbar ist.
- Skriptänderungen: Fresh-Install explizit geschützt, WIM-Index 6 (Windows 11
  Pro), Product-Key-Dialog unterdrückt, Support-ISO mit VirtIO-Treibern und
  Postinstall-Skript, ZVOL-Boot nach Installation, automatischer erster
  ISO-Tastendruck, Hugepage-Fallback und 12-GiB-Testbetrieb.
- Letzte Logprüfung: ZFS ONLINE/no data errors; QEMU ohne Datenträgerfehler;
  KVM-Speicherdruck wegen Hostbelegung, nicht wegen ZFS.

## Prüfung 2026-09-27 14:20 CEST (Windows-OOBE erreicht)

- Windows-Panther-Logs wurden read-only aus der NTFS-Partition des ZVOLs
  gelesen. Ursache des vorherigen Abbruchs war eine ungültige
  `Microsoft-Windows-Shell-Setup/RunSynchronous`-Angabe im `specialize`-Pass
  (`0x80220001`), nicht ZFS oder QEMU. Der problematische Block ist entfernt.
- Neuer Fresh-Install verwendet `compression=off`, `primarycache=metadata`,
  SATA-Datenträger und `e1000e`-Netzwerk für die eingebauten WinPE/OOBE-Treiber.
- Die Installation lief automatisch durch Region, Tastatur, Datenträger,
  Edition und Neustarts. Netzwerk-OOBE funktioniert. Aktueller Bildschirm ist
  die Siemens-Geschäfts-/Schulkonto-Anmeldung; MFA/Intune bleibt bewusst beim
  Benutzer.

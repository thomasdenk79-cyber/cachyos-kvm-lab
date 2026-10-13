# Review 5 – FRISCH-SESSION-Perspektive (2026-10-13)

Rolle: fremder Agent/Operator ohne Vorkenntnis, nur `cachyos-kvm-lab/TODO.md` +
`workstation-setup/docs/virtualisierung-labor-20261013.md` als Einstieg.
Fragestellung: Wo haengt ein Fremder nach dem naechsten Reboot, oder was koennte er
aus Unkenntnis kaputtmachen? Je Punkt: konkreter Fix-Wortlaut.

## Die 10 Stellen

### 1. Reboot-Zeitpunkt: zwei aktive Windows-Installer + die eigene Agent-Session laufen auf dem Host
TODO sagt zwar "Reboot nur nach Benutzerfreigabe", aber ein Frisch-Agent sieht nur
"Fix = Reboot" und koennte ungefragt neu starten: `vb-win11` (Windows-Installation
laeuft!) und VMware GW2-Install werden dreckig abgeschaltet, derBlackwell-Inferenzstapel
Pennyroyal + LiteLLM (auf dem der Agent selbst haengt!) sterben ebenfalls.
- **Fix:** Vor jedem Reboot zwingend pruefen und freigeben lassen:
  `VBoxManage list runningvms; pgrep -af vmware-vmx; sudo virsh list --all`.
  Nach dem Reboot gilt die Session-Regel aus current-work.md: Pennyroyal-Weights
  brauchen ~170 s, Gesundheit nur so pruefen:
  `systemctl --user restart pennyroyal && for i in $(seq 1 30); do sleep 10; curl -sf http://127.0.0.1:8001/health && break; done`
  (Single-Shot-Pruefung immer False-Negative).

### 2. IOMMU-Nachweis kaputt geschrieben: grep ohne -E → Fehlalarm, und der Revert-sed ist zu wortgenau
TODO Zeile 24 empfiehlt `dmesg | grep -i 'iommu|dmar'`. Das ist Basic-Regex –
das Pipe-Zeichen wird literal gesucht, die Ausgabe bleibt leer. Ein Frisch-Agent
interpretiert das als "IOMMU nicht aktiv" und koennte panisch revertingieren oder
stundenlang suchen. Umgekehrt ist der Dauerhaft-Revert aus Zeile 26
(`sed -i 's/ intel_iommu=on iommu=pt//'`) nur wirksam, wenn exakt diese
Schreibweise mit Leerzeichen in GRUB_CMDLINE steht – stiller No-Op moeglich.
- **Fix:** Pruefen mit `cat /proc/cmdline` und
  `dmesg | grep -iE 'DMAR|IOMMU'` und
  `find /sys/kernel/iommu_groups/ -type l | wc -l` (muss >0 sein).
  Revert nur mit Verifikation:
  `sudo sed -i 's/ intel_iommu=on iommu=pt//' /etc/default/grub && sudo update-grub && grep -c intel_iommu /etc/default/grub`
  (die 0 muss sein, sonst hat der sed nichts getroffen – dann Datei von Hand
  anpassen, Backup `/etc/default/grub.bak-pre-iommu-20261013` vorhanden).
  Boot-Notfall: GRUB-Menue `e`, die zwei Woerter loeschen, `Strg-X`.

### 3. Alte vmwrite-Panik nach Reboot falsch lesen → Modul-Reload-Versuch → erneuter Lockdown
Nach dem Reboot koennte eine Domain weiterhin als `paused`/`shutoff` mit
fehlerhaftem Zustand auftauchen, oder ein Frisch-Agent kennt den Verifizierungsschritt
nicht und faengt mit `modprobe -r kvm_intel` an – dokumentiert unmöglich
(Refcount=2-Leak), es folgen fruchtlose `rmmod -f`-/Reboot-Spiralen.
- **Fix:** Modul-Reload bleibt tabu. Korrekte Verifikation direkt nach Reboot:
  `sudo dmesg | grep -ciE 'vmwrite|Invalid VMCS'` → erwartungsgemaess 0, dann
  `sudo virsh start kvm-siemens && sleep 10 && sudo virsh domstate kvm-siemens`
  → muss `running` liefern. Bei hangender Domain nur `sudo virsh destroy kvm-siemens`
  + erneut `start`; **niemals** `virsh undefine --remove-all-storage`
  (AGENTS.md Regel 5 – haengende ISOs, dabei wandert die Datenplatte mit).

### 4. kvm-venus: libvirt 10.0 verschluckt stille das spice-socket-Attribut → TCP+GL → Startfail
Der in TODO 3a beschriebene Fehler ist persistent: Wird die VM falsch definiert,
landet SPICE auf TCP und QEMU ablehnt `gl=on` ("SPICE GL support is local-only").
Ein Frisch-Agent sieht nur "VM startet nicht" im `virsh start`.
- **Fix:** Sauber neu definieren mit exakt diesem Grafikblock, OHNE `<listen>`-Element:
  `<graphics type='spice' socket='/var/lib/libvirt/qemu/kvm-venus.spice' autoport='no' keymap='de'>`
  via `sudo virsh define /home/z000g9hu/vm-lab/kvm-venus.xml`. Danach Pflichtkontrolle:
  `sudo virsh dumpxml kvm-venus | grep -o "socket=[^ ']*"` → muss den Unix-Pfad
  zeigen. Falls wieder dropped: libvirt-10.0-Schema pruefen
  (`sudo virsh help define`) + Roundtrip-Test mit frischem `sudo virsh edit kvm-venus`.

### 5. Viewer verbinntet nicht, weil die Umgebungsvariablen fehlen → sieht aus wie defekte VM
Der Viewer-Kommando aus TODO braucht zwingend Display-/Runtime-Env; eine nackte
Agent-Shell ohne `DISPLAY`/`XDG_RUNTIME_DIR` liefert nur "Cannot open display" –
der Frisch-Agent haelt das fuer einen Grafikdefekt der VM.
- **Fix:** Vollstandiges Kommando:
  `env DISPLAY=:1 WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000 virt-viewer -c qemu:///system "spice+unix:///var/lib/libvirt/qemu/kvm-venus.spice"`.
  Alternativ-Fundort des URIs: `sudo virsh domdisplay kvm-venus`. Erst nach
  erfolgreichem `running` + Socketdatei-Check
  (`ls -l /var/lib/libvirt/qemu/kvm-venus.spice`) ueber Viewer-Defekt urteilen.

### 6. SeaBIOS-/nested-VMX-"Verbesserung" → Triple-Fault und neue VMCS-Korruption
TODO 3b/c warnt: SeaBIOS kann kein virtio-vga-GL (Triple-Fault!), und guestseitiges
`vmx`/`svm` Anschalten ist giftig, weil das BIOS nested VT-x deaktiviert hat –
genau dieser Mix hat den Host-KVM-Bug (Punkt 3) erst erzeugt. Ein Frisch-Agent, der
"die CPU-Flags" optimiert, macht den Host erneut kaputt bis zum naechsten Reboot.
- **Fix:** UEFI/OVMF und vmx+svm-disable sind Contract, nicht Option. Kontrolle:
  `sudo virsh dumpxml kvm-venus | grep -E 'loader|vmx|svm'` → OVMF-Pfad vorhanden,
  `policy='disable'` fuer vmx und svm. Aenderung nur dokumentieren, nicht "testen".

### 7. Archiviertes Backup-XML liegt herum → ein `virsh define` damit rollt alle kvm-siemens-Tunings zurück
In `~/vm-lab/` liegt `kvm-siemens-backup-20261012-2346.xml` (PRE-Tuning: 8 vCPU,
QXL 64 MB, image compression off). Ein Frisch-Agent haelt das natuerlich fuer die
"Soll-Konfiguration" und definiert es ein – Tuning kommentarlos weg.
- **Fix:** Diese Datei dient nur der manuellen Wiederherstellung, niemals definieren.
  Live-Soll-Zustand nach Reboot pruefen:
  `sudo virsh dumpxml kvm-siemens | grep -E '<vcpu|262144|auto_glz'`
  → erwartet: 16 vCPU, `ram='262144' vram='262144'`, `<image compression='auto_glz'/>`.

### 8. Snapshot-Mechanik missverstanden: Revert rollt nur die Disk, und ein Delete ohne `--metadata` risss die External-Backing-Kette
`pre-tune-20261013` ist ein DISK-ONLY EXTERNAL-Snapshot. Ein Frisch-Agent
(1) wundert sich, warum nach Revert das XML-Tuning noch steht (ist so: external
betreffen nur den Disk-Zustand), und (2) loescht den Snapshot mit dem
Default-Kommando und erwischt dabei das externe Pruefplatten-Image, was die
Backing-Kette des aktuellen qcow2 unbrauchbar machen kann.
- **Fix:** Anwenden nur bei verifiziertem Tuning-Fehlschlag:
  `sudo virsh snapshot-revert kvm-siemens pre-tune-20261013`.
  Loeschen NUR so und erst nach Erfolg:
  `sudo virsh snapshot-delete kvm-siemens pre-tune-20261013 --metadata`
  (`--metadata` ist Pflicht – ohne Flag wird die Disk-Ebene angefasst).
  Ketten-Check vor jedem geloelten Loeschdenken:
  `qemu-img info --backing-chain /var/lib/libvirt/images/kvm-siemens*.qcow2`.

### 9. vboxusers-Rechte nach Reboot: frische Session noetig, Oracle-Init ueberschreibt Udev-Gruppe gern wieder
Doku-Halbfakt: User ist in `vboxusers`, aber Gruppenmitgliedschaft greift erst im
neuen Login, und `/etc/udev/rules.d/60-vboxdrv.rules` konkurriert mit Oracles
eigenem Init – nach Reboot kann `/dev/vboxdrv` wieder Gruppe `root` tragen.
Symptom fuer den Fremden: `VBoxManage list vms` → "Could not open the default
machine" / vboxdrv-Fehler, VBox-VM "weg".
- **Fix:** Diagnostics: `id -nG | tr ' ' '\n' | grep -x vboxusers` und
  `ls -l /dev/vboxdrv`. Gruppe root? → `sudo systemctl restart vboxdrv`
  (Override `vboxdrv.service.d/60-group.conf` setzt sie dann). Kein Logout?
  → einmalig `sg vboxusers -c 'VBoxManage list vms'` als Uebergang.

### 10. Ada-Passthrough-Spike wird zu frueh gezogen → Host verliert saemtliche Videoutputs
Die IOMMU-Infrastruktur ist nach dem Reboot da – fuer einen ehrgeizigen Frisch-Agenten
sieht der Ada-Spike (TODO Backlog) nach "mach ich jetzt" aus. Aber: Lenovo leitet
HDMI/DP ueber die Ada, der interne eDP haengt an der iGPU, ein DisplayLink fehlt –
ein verfruehtes vfio-Bind + initramfs-Rebuild kann den Host displaylos machen, und
die ACS-Vorbedingungen sind nie getestet.
- **Fix:** Zurückstellen – die Doku sagt ausdruecklich "vfio-Bindings bewusst NOCH
  nicht eingerichtet (additiv, später)". Vor jedwedem Spike:
  `sudo dmesg | grep -i acs` und Blocker-Analyse
  (`nvidia-desktop` ist der iGPU-Pfad-Blocker-Lenk) dokumentieren; kein
  `/etc/modprobe.d/vfio.conf` und kein `initramfs`-Rebuild vor ausdruecklicher
  Freigabe; Host ohne Headless-Notausgang (SSH genuegt?) gar nicht anfassen.

## Nachschlag (knapp am Top-10-Rand)
- TODO-Backlog: `rm -rf ~/snap/steam` als "optional cleanup" markiert – vor dem
  Loeschen erst die Migration endgueltig verifizieren:
  `ls ~/.steam/debian-installation/steamapps/ | wc -l` (6 Manifeste erwartet).
- `kvm-venus`-Erststart faehrt von der CachyOS-ISO im Loop; ein Frisch-Agent koennte
  die ISO "zum Platzsparen" aushaengen, bevor die Installation durch ist
  (`/var/lib/libvirt/images/cachyos-desktop-linux-260809.iso` bis zum Abschluss
  eingeklinkt lassen).

## Kurzfazit
Groesste Fremd-Agent-Gefahren: (a) Reboot ohne Freigabe, (b) der bughafte
IOMMU-Grep-Zeile im TODO, der zur Rueckabwindung falscher Diagnose fuehrt,
(c) das Backup-XML und die Snapshot-Loeschung, die beide Tuning/Rollback
unwiderruflich zerstoeren koennen, (d) verfruehtes vfio-Binding mit Totalverlust
der Host-Displayausgaenge.

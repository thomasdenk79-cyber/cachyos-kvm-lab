# Review 1 — Technische Korrektheit (VM-Labor, Live-Prüfung 2026-10-13)

Prüfer: Subagent „Technische Korrektheit". Alle Prüfungen read-only gegen Live-System
(KDE neon 24.04 / Ubuntu-noble-Basis, Kernel 7.0.0-38-generic, QEMU 8.2.2, libvirt monolithischer
modus: libvirtd active / virtqemud inactive).

## Befunde (8)

### B1 — kvm-venus.xml: XML schema-invalid; `socket=` + `autoport='no'` verletzt RNG — Severity: HOCH
`virt-xml-validate /home/z000g9hu/vm-lab/kvm-venus.xml` -> FEHLER (Zeile 29, devices/graphics).
Bisect: Entfernen von `<graphics>` allein macht das Dokument gültig; Entfernen NUR des
`socket`-Attributs -> OK. Ursache: `socket='…'` zusammen mit `autoport='no'` ist im
libvirt-RNG (noble, libvirt 10.x) keine erlaubte Kombination. Korrekte moderner Form:
`<listen type='socket' socket='…'/>` (Variante wurde erstellt und validiert OK: fixed.xml).
Fix-Kommando:
```
sed -i "s|<graphics type='spice' socket='\\(/[^']*\\)' autoport='no' keymap='de'>|<graphics type='spice' keymap='de'>\n      <listen type='socket' socket='\\1'/>|" /home/z000g9hu/vm-lab/kvm-venus.xml && virt-xml-validate /home/z000g9hu/vm-lab/kvm-venus.xml
```

### B2 — kvm-venus gar nicht im Hypervisor definiert (Doku-Behauptung falsch) — Severity: HOCH
`sudo virsh -c qemu:///system list --all` zeigt NUR `kvm-siemens` (shutoff). Kein
`/var/lib/libvirt/qemu/nvram/kvm-venus_VARS.fd`, kein libvirt-AppArmor-Profil für die Venus-UUID.
current-work.md sagt „definiert via ~/vm-lab/kvm-venus.xml" — nicht haltbar (passt zu B1: Define
wahrscheinlich verworfen oder nie durchgeführt).
Fix-Kommando: `sudo virsh define /home/z000g9hu/vm-lab/kvm-venus.xml` (erst nach B1-Fix)

### B3 — SPICE-Socket unter /var/lib/libvirt/qemu: AppAir-Regel für QEMU-Gastprofil fehlt — Severity: MITTEL
Profile sind enforce (169 Profiles, libvirtd/virt-aa-helper enforce). Aber
`/etc/apparmor.d/abstractions/libvirt-qemu` erlaubt nur `owner /{dev,run}/shm/spice.*` (Zeile 77)
und nvram-Dateien (Zeilen 306/307) — KEIN Write-Recht auf `/var/lib/libvirt/qemu/*.spice`.
virt-aa-helper nimmt nur Disk-Quellen auf. Konsequenz: beim ersten Venus-Start wird das
Socket-Binden vom enforce-Profil denied (bisher keine DENIED-Einträge in dmesg, da venus nie
lief — Risiko ungetestet). Local-Include existiert (Zeile 316), Datei fehlt noch.
Fix-Kommando:
```
echo '  owner /var/lib/libvirt/qemu/*.spice rw,' | sudo tee -a /etc/apparmor.d/local/abstractions/libvirt-qemu && sudo apparmor_parser -r /etc/apparmor.d/abstractions/libvirt-qemu
```

### B4 — Venus-Rendernode /dev/dri/renderD128 für QEMU-Prozess nicht erreichbar — Severity: MITTEL
renderD128 = Intel-iGPU (PCI 00:02.0), Gruppe `render`, ACL nur für `z000g9hu` (+rw),
aber `id libvirt-qemu` = Gruppen `kvm,libvirt-qemu` — OHNE render, kein ACL-Eintrag.
`<gl rendernode='/dev/dri/renderD128'/>` würde beim Start open() -> Permission denied.
Fix-Kommando: `sudo setfacl -m u:libvirt-qemu:rw /dev/dri/renderD128` (persistent: udev-REGEL/EPP; alternativ einmalig je Boot)

### B5 — vb-win11: TPM in .vbox konfiguriert, aber NICHT aktiv — Severity: MITTEL
`vb-win11.vbox` enthält `<TrustedPlatformModule type="v2_0" location="…/vb-win11-tpm"/>`,
ABER: `VBoxManage showvminfo --machinereadable` zeigt KEINEN TPM-Wert, und das State-Verzeichnis
`vb-win11-tpm/` (bzw. tpm.cfg) existiert im VM-Ordner NICHT (nur Logs, nvram, vbox, vdi).
Deutung: Einstellung wurde am laufenden VM geändert und greift erst nach Neustart — die
behauptete TPM-Grundlage der Win11-Installation ist aktuell nicht belegt.
Fix-Kommando: `VBoxManage showvminfo vb-win11 --machinereadable | grep -i tpm` (nach Shutdown+Start erneut prüfen; Verzeichnis muss dann existieren)

### B6 — vb-win11: Clipboard ist auf „disabled", nicht bidirektional — Severity: NIEDRIG
`Clipboard Mode: disabled` / `.vbox` ohne ClipboardMode (Default). Prüfpunkt „bidirectional
braucht Gasttools": Gasttools sind vorhanden und aktiv (GuestAdditionsVersion 7.2.20 r175154,
RunLevel=3, Base Driver/System Service/Desktop Integration aktiv) — Voraussetzung erfüllt,
nur die Konfiguration selbst ist nicht gesetzt.
Fix-Kommando: `VBoxManage clipboard vb-win11 bidirectional`

### B7 — Benutzer nicht in libvirt-Gruppe: dokumentierter virsh-Workflow nur mit sudo — Severity: MITTEL
`id`: Gruppen adm,cdrom,sudo,dip,plugdev,tss,lpadmin,sambashare — KEIN `libvirt`.
`virsh -c qemu:///system list --all` als User: „Failed to connect socket … Keine Berechtigung".
Damit sind alle Doku-Kommandos (virsh/showvminfo-Parallelen) für den User so nicht ausführbar.
Fix-Kommando: `sudo usermod -aG libvirt $USER` (danach Session neu anmelden)

### B8 — KVM-Host-Blocker unverändert aktiv (Reboot steht aus) — Severity: HOCH (Blocker, bestätigt)
`dmesg`: exakt 11 vmwrite-Zeilen (1× „vmwrite_error: 153 callbacks suppressed" + 10× failed),
alle im selben Burst bei Timestamp 40823.737 (= ~23:57 Uhr, Incident von gestern).
NEUE Einträge seit letztem Test: 0. `lsmod`: kvm_intel refcnt weiterhin 2 (Leak), /dev/kvm
vorhanden. Damit bleibt „keine neue KVM-VM startet" korrekt; Venus-Start ist unabhängig von
B1–B4 blockiert.
Fix-Kommando: `sudo systemctl reboot` (geplanter User-Reboot; bringt zugleich intel_iommu=on iommu=pt)

## Geprüft i.O. (keine Befunde)

1. **SATA-Controller in kvm-venus.xml: VORHANDEN** (Zeilen 45–47, ich9 ahci slot 0x1f.2,
   index=0 passt zur cdrom-Adresse) — die Verdachtsfrage ist unbegründet.
2. **video virtio ohne `<driver name='qemu'/>`: zulässig** — `accel3d='yes'` allein ist
   schema-konform; libvirt erzeugt virtio-gpu-gl mit Default-Renderer. (Empirisch: fixed.xml
   mit Listen-Fix validiert vollständig.) `vram='131072'` für virtio wird nur ignoriert (kosmetisch).
3. **io='io_uring' cache='none' auf qcow2: OK** — QEMU 8.2.2 ist gegen liburing.so.2 gelinkt
   (`ldd`), Kernel 7.0 unterstützt io_uring. Verlangter Proxy:
   `qemu-system-x86_64 -device help | grep -c virtio-gpu-gl` = **2** (virtio-gpu-gl-pci/-device vorhanden).
4. **memballoon + hyperv mode='custom' (relaxed/vapic/spinlocks) in beiden XMLs: korrekt**
   (spinlocks retries 8191/8192 gültig; hypervclock-Timer gesetzt; RNG-ok nach B1-Fix).
5. **QXL vram=262144 KiB (256 MiB) in kvm-siemens-tuned.xml: QEMU akzeptiert das** —
   Live-Test (kein virsh-define!): `qemu-system-x86_64 -M q35 -display none -S -device
   qxl-vga,ram_size=268435456,vram_size=268435456` lief 5 s fehlerfrei (nur timeout-Exit 124),
   keine Truncation-Meldung; Property vram_size ist uint64, kein max-VRAM-Clamp sichtbar.
6. **Topologie 1 socket/16 cores/threads=1 plausibel** — Host: 32 logische CPUs, 2 Threads/Kern
   = 16 Physische Kerne; Gast = exakte Kernzahl ohne SMT, passt zu vcpu=16.
7. **Live-Definition kvm-siemens == tuned-Datei** — Inactive-dumpxml difft nur in
   Anführungszeichen/Whitespace; vram/ram/tdisksource identisch; aktiver Disk-Pfad zeigt korrekt
   auf das externe Snapshot-Overlay `kvm-siemens.pre-tune-20261013` (111 MiB, backing =
   kvm-siemens.qcow2 200 GiB, corrupt: false); Snapshot `pre-tune-20261013` in libvirt gelistet
   (shutoff). Backing-Kette gesund.
8. **Steam: deb-Version läuft tatsächlich** — 4 Prozesse (`ps -eo args | grep -c '[s]team'` = 4),
   Pfade ausschließlich `/home/z000g9hu/.steam/debian-installation/...` + steam-runtime-launcher-service;
   `snap list steam` -> keine Snaps installiert; OVMF-/ISO-Pfade der Venus vorhanden
   (ISO libvirt-qemu:kvm korrekt inventarisiert).

## Gesamturteil
Kern-Tunings (Siemens) sind live-korrekt übernommen und QEMU-seitig validiert. Die
Venus-Seite ist dagegen in drei Schichten kaputt: Schemafehler (B1), nie definiert (B2),
und selbst nach Definition durch AppArmor (B3) + Rendernode-ACL (B4) + Host-KVM-State (B8)
startblockiert. VBox: TPM-Behauptung nicht verifizierbar (B5), Clipboard anders als dokumentiert (B6).
Reihenfolge des sicheren nächsten Schritts: B8 Reboot -> B1 -> B2 -> B3/B4 -> `virsh start kvm-venus`.

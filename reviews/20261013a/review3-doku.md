# Review 3 – Doku & Handover (Frischlings-Perspektive) – 2026-10-13

Gegenstand: cachyos-kvm-lab/TODO.md · workstation-setup/docs/virtualisierung-labor-20261013.md ·
hermes-memory-workspace/context/current-work.md (Abschnitt Virtualisierungslabor) · /tmp/reviews/ (vorher leer).

Live verifiziert (diese Session): `loginctl show-user z000g9hu` → Display=4, Linger=yes;
`systemctl --user show-environment` → XAUTHORITY=/run/user/1000/xauth_VZSvcw (zufälliger Suffix!),
DISPLAY=:1, WAYLAND_DISPLAY=wayland-1; /dev/dri: renderD128→i915, renderD129/130→nvidia;
`sudo virsh list --all` → nur kvm-siemens (shut off), **kvm-venus NICHT definiert**;
cachyos-kvm-lab: main == origin/main, TODO.md ist bereits committet (f409418);
~/vm-lab/kvm-venus.xml vorhanden, enthält bereits vmx/svm-disable (Zeile 8) und io='io_uring' (Zeile 32).

Leitfrage: Kann ein frischer Engineer/KI-Session nach Reboot ohne Kontext morgen weiterarbeiten?
Antwort: nahezu, aber 3 Befunde sind akut irreführend (F1–F3), der Viewer-Aufruf ist nach Reboot
garantiert nicht copy-paste-fähig (F4).

---

## F1 – Widersprüchlicher Status von kvm-venus: „definiert“ vs. nicht definiert
**Severity: HOCH.** TODO.md Z.27ff („Define/Start-Form folgt“) ist korrekt; Doku-Tabelle Z.14
(„definiert“), Doku Z.47 („persistent“) und current-work Z.13 („definiert via …“) sind falsch –
live bestätigt: `virsh domstate kvm-venus` → error. Ein Frischling würde `virsh start kvm-venus`
versuchen und verwirrt scheitern.
**Patch (workstation-setup-Doku, Tabelle):**
```diff
-| kvm-venus          | KVM q35, CachyOS virtio-gpu+GL | definiert, Start blockiert durch KVM-Kernelbug  |
+| kvm-venus          | KVM q35, CachyOS virtio-gpu+GL | NOCH NICHT definiert; XML liegt unter ~/vm-lab/kvm-venus.xml (define+start nach Reboot) |
```
**Patch (current-work.md):**
```diff
-- `kvm-venus` (CachyOS virtio-gpu+GL): definiert via `~/vm-lab/kvm-venus.xml`,
-  Start blockiert.
+- `kvm-venus` (CachyOS virtio-gpu+GL): NICHT definiert (nur XML unter
+  `/home/z000g9hu/vm-lab/kvm-venus.xml`, Stand verifiziert 13.10. via `sudo virsh list --all`).
+  Naechster Schritt nach Reboot: `sudo virsh define /home/z000g9hu/vm-lab/kvm-venus.xml`.
```

## F2 – Viewer-Zeilen nach Reboot nicht copy-paste-fähig: XAUTHORITY fehlt, DISPLAY hartkodiert
**Severity: HOCH.** TODO.md Z.40f nennt nur `DISPLAY=:1 WAYLAND_DISPLAY=wayland-1
XDG_RUNTIME_DIR=/run/user/1000`. Kein XAUTHORITY – existiert aber zwingend und hat einen
zufälligen Suffix (`/run/user/1000/xauth_VZSvcw`), der **nach jedem Reboot neu erzeugt wird**.
Zudem meldet `loginctl show-user` aktuell Display=**4**, die 1 ist also auch nicht garantiert.
**Patch (TODO.md, Punkt 3 Viewer):**
```diff
-    - Viewer: `virt-viewer "spice+unix:///var/lib/libvirt/qemu/kvm-venus.spice"`
-      (mit DISPLAY=:1 WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000).
+    - Viewer (nach Reboot, Umgebungsvariablen NICHT raten – neu ermitteln):
+      `loginctl show-user z000g9hu | grep ^Display` und
+      `systemctl --user show-environment | tr ' ' '\n' | grep -E 'XAUTHORITY|DISPLAY|WAYLAND'`
+      (XAUTHORITY liegt typisch unter /run/user/1000/xauth_* mit zufaelligem Suffix).
+      Aufruf: `sudo XDG_RUNTIME_DIR=/run/user/1000 DISPLAY=:<N> WAYLAND_DISPLAY=wayland-1 \
+      XAUTHORITY=<wie ermittelt> virt-viewer "spice+unix:///var/lib/libvirt/qemu/kvm-venus.spice"`
+      (sudo, weil der SPICE-Socket in /var/lib/libvirt/qemu/ root-only ist – nach erstem Start
+      Rechte real pruefen und hier korrigieren).
```
Gleicher Hinweis gilt sinngemäß für den bestehenden Punkt 4 (kvm-siemens-Viewer).

## F3 – TODO-Checkbox „cachyos-kvm-lab committen/pushen“ ist veraltet
**Severity: MITTEL.** TODO.md Z.84 `[ ] dieses TODO.md committen/pushen` – tatsächlich ist es
committet und main == origin/main (f409418). current-work Z.22 („geclont, gefüllt, gepusht“) ist
richtig. Wer morgen die Checkliste abarbeitet, verschwendet Zeit oder doppel-committet.
**Patch (TODO.md):**
```diff
-- [ ] cachyos-kvm-lab: dieses TODO.md committen/pushen.
+- [x] cachyos-kvm-lab: dieses TODO.md committen/pushen (Commit f409418, main==origin/main,
+      verifiziert 2026-10-13).
```

## F4 – Rendernode D128/D129: aktueller Wert ok, aber Archiv widerspricht ohne Warnung
**Severity: MITTEL.** Doku Z.56 „i915 renderD128“ ist live korrekt. Aber im selben Repo liegen
Archivskripte mit `RENDER_NODE=...renderD129` (cachyos-venus-direct-qemu.sh) und Logs, die D129
als SPICE-Node testen (NVIDIA, bekannt defekt). Ein Frischling, der über grep im Repo landet,
erwischt garantiert die falsche Default. Fehlender Kreuzverweis-Patch (workstation-setup-Doku):
```diff
-- Rendernode: i915 renderD128 (NVIDIA-EGL auf virtio-gpu-gl-Hostpfad ist bekannt
-  defekt; Ada bleibt frei für VMware, Blackwell bleibt für Pennyroyal/sglang).
+- Rendernode: i915 renderD128 (live verifiziert 13.10.: `readlink
+  /sys/class/drm/renderD128/device/driver`; renderD129/130 = nvidia).
+  ACHTUNG: Material unter cachyos-kvm-lab/archive/legacy-repo-20260922/ useht noch
+  renderD129 (NVIDIA) – Negativtest, `eglInitialize failed: EGL_NOT_INITIALIZED`,
+  nur informativ, NIEMALS als Default uebernehmen. Ada bleibt frei fuer VMware,
+  Blackwell bleibt fuer Pennyroyal/sglang.
```

## F5 – „warum vmx/svm disable“ und „warum SeaBIOS scheitert“: Kausalkette + Gefahr fehlt
**Severity: HOCH.** Beide Dateien nennen nur die Kurzformel. Der entscheidende Zusammenhang
ist nirgends dokumentiert: Genau der Triple-Fault einer virtio-gl-VM wird als Hauptverdaechtiger
der VMCS-Korruption genannt (TODO Z.11f) – und SeaBIOS provoziert nachweislich Triple-Faults.
Ein Frischling, der das nicht verbindet, riskiert mit einem SeaBIOS-Experiment den naechsten
Host-Reboot. **Patch (TODO.md Z.37-39):**
```diff
-      (b) SeaBIOS → Triple-Fault: UEFI-OVMF-Pfad beibehalten.
-      (c) vmx/svm disable bleiben (BIOS hat nested VT-x disabled; sonst
-      KVM-VMCS-Korruption wie oben!).
+      (b) SeaBIOS → Triple-Fault (SeaBIOS kann kein virtio-vga-gl/UEFI-GOP-Scan;
+      Bootlauf laeuft in Triple-Fault). UEFI-OVMF-Pfad ist PFLICHT: Ein weiterer
+      Triple-Fault ist der wahrscheinliche Ausloeser der aktuellen Host-VMCS-
+      Korruption – Experiment damit kostet den naechsten Gesamt-Reboot.
+      (c) vmx/svm im Gaest-CPU bleiben disable (stehen bereits in
+      ~/vm-lab/kvm-venus.xml Zeile 8: <feature name='vmx' policy='disable'/> + svm).
+      Grund: host-passthrough wuerde dem Gast VMX/_nested-VT-x zeigen, das BIOS
+      hat nested VT-x aus → GastKernel ruft VMXON auf ungueltigem Host auf →
+     Fault → erneut moegliche VMCS-Korruption.
```

## F6 – io_uring: nirgends erklärt, aber real in kvm-venus.xml (Zeile 32) und im Altkontext
**Severity: MITTEL.** In allen drei Aktiv-Dateien kommt `io_uring` kein einziges Mal vor; das
persistente XML und TODO-WIN11-REBOOT.md nutzen es (`io='io_uring'`). Wer morgen `dumpxml`
vergleicht, findet einen nicht dokumentierten, nicht erklärten Parameter und weiß nicht, ob er
Teil des Tunings oder Altlast ist. **Patch (workstation-setup-Doku, kvm-venus-Abschnitt):**
```diff
+  Disk-Treiber: `cache='none' io='io_uring' discard='unmap'` – io_uring statt
+  native-AIO, weil es den Block-Lookup einspart und mit Thread-Mode-IO
+  (iothread) den qcow2-Pfad beschleunigt; identisch zum Win11-Runbook
+  (TODO-WIN11-REBOOT.md). Kein Experiment, bewusst gesetzt.
```

## F7 – Relative Pfadreferenzen: für eine Frischlings-Session nicht eindeutig
**Severity: MITTEL.** TODO.md Z.4f verweist auf `workstation-setup/docs/...` und
`hermes-memory-workspace/context/...` ohne Basisverzeichnis; current-work.md Z.8 ebenso;
kein der drei Dokumente nennt den absoluten Pfad/Remote von cachyos-kvm-lab. Nach Crash+Reboot
ohne Session-Kontext ist „workstation-setup/…“ nur ratbar (es existiert ~/work/…). **Patch (TODO.md):**
```diff
-Arbeitsübernahme-Punkt nach der Nacht-Session 2026-10-12/13. Vollprotokoll der
-Aktionen: `workstation-setup/docs/virtualisierung-labor-20261013.md`
-(gepusht, Commit dort), Kurzfassung: `hermes-memory-workspace/context/current-work.md`.
+Arbeitsübernahme-Punkt nach der Nacht-Session 2026-10-12/13. Repo:
+`/home/z000g9hu/work/cachyos-kvm-lab` (github.com/thomasdenk79-cyber/cachyos-kvm-lab, main).
+Vollprotokoll: `/home/z000g9hu/work/workstation-setup/docs/virtualisierung-labor-20261013.md`
+(gepusht), Kurzfassung: `/home/z000g9hu/work/hermes-memory-workspace/context/current-work.md`.
```

## F8 – Kaputter Prüfbefehl: `dmesg | grep -i 'iommu|dmar'` liefert nichts
**Severity: MITTEL.** Basic-Grep behandelt `|` literale; der Frischling hält IOMMU für inaktiv.
**Patch (TODO.md Z.24):** `dmesg | grep -iE 'iommu|dmar'` (ebenso in Z.24 `wc -l`-Zeile ok).
Ergänzung sinnvoll: erwartetes Ergebnis benennen, z. B. „>0 Gruppen = aktiv;
`dmesg` zeigt `DMAR: IOMMU enabled`“.

## F9 – Tippfehler/Stil (git-blame-unwürdig, aber sammelpatchenswert)
**Severity: NIEDRIG.**
- TODO.md Z.7: `## SofortBLOCKER` → `## Sofort-BLOCKER:` (fehlendes Leerzeichen).
- TODO.md Z.34: „**ifconfig** gegen `sudo virsh dumpxml | grep -o socket=...`“ – Satzfragment
  mit fehlplatziertem „ifconfig“; gemeint ist wohl „gegenprüfen mit“. Vorschlag:
  „Gegenprüfen nach Start: `sudo virsh dumpxml kvm-venus | grep -o \"socket=[^ ]*\"`“.
- TODO.md Z.94: „neweres“ → „neueres“.
- TODO.md Z.44: „after reboot SPICE-Flüssigkeit“ → „nach Reboot SPICE-Flüssigkeit“.
- TODO.md Z.45: „QXL 262144“ → „QXL vram 262144 KiB“; TODO.md Z.53 „auf 256 gestellt“ → „256 MB“.
- Rechtschreibstil: current-work.md durchgehend ASCII (ue/ss), die anderen beiden Docs mit
  echten Umlauten. Innerhalb von Dateien konsistent – akzeptabel, aber die TODO.md sollte
  Umlaut-Stil nicht mischen (sie tut das derzeit nicht – ok).

## F10 – Fehlender Einzeiler: Reboot-Freigabe-Kopplung an User-Tests
**Severity: NIEDRIG.** TODO.md Z.16f erwähnt die Nebenbedingung (VMware/VBox-Installationen
laufen), aber nicht, dass ein Reboot die laufende GW2-/Win11-Installation im Gast verwurstet.
Ergänzen: „Reboot terminiert erst, wenn GW2- und Win11-Installation abgeschlossen oder sauber
pausiert sind (User-Bestätigung einholen).“

---

## Gesamtbild
Pfade sind bis auf F7 eindeutig und live verifizierbar; Startbefehle für virsh/Reboot-Check
(TODO Z.15) sind vorbildlich copy-paste-fähig. Kritisch sind ausschließlich der venus-Status
(F1) und der Viewer-Umgebungsblock (F2) – beides würde morgen sofort Zeit fressen.
Deutsch/Englisch-Mix ist überall funktionell konsistent (nur F9-Einzelstellen).

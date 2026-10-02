# Windows-11-GPU-Testmatrix

Dieser Bereich testet die Grafikpfade der libvirt-Domain
`windows11-generic-test` getrennt von der Ubuntu-mLinux-Matrix. Jeder Lauf
sichert die Domain-XML, prüft die effektiven QEMU-Argumente und schreibt
Rohlogs ausschließlich nach `~/system-setup/logs/windows11-gpu/`.

Die sichere Windows-KVM-Grundoptimierung ist in
`scripts/windows11-kvm-performance.sh` automatisiert. Sie setzt `memfd`,
SPICE-Streaming `off` und prüft `host-passthrough`, I/O-Thread,
`cache=none`/`discard=unmap` und VirtIO-DOD. `virtio-vga-gl` wird nicht als
Standard gesetzt, da der Windows-VirtIO-DOD-Gast dafür keinen verifizierten
VirGL-Treiberpfad hat.

VirtIO-Tablet und VirtIO-Keyboard sind zusätzlich zu USB/PS/2 als Fallback
definiert. Das eingebundene VirtIO-ISO enthält `vioinput`; sobald der Treiber
im Windows-Gast aktiv ist, kann Windows den latenzärmeren VirtIO-HID-Pfad
verwenden.

Profile:

- `baseline-intel-virtio-vga`: `virtio-vga` mit SPICE über Intel
  `/dev/dri/renderD128`. Aktueller funktionierender Referenzpfad.
- `virtio-vga-gl-intel`: `virtio-vga-gl` über Intel. Negativtest: QEMU
  startete, aber SPICE hatte keinen nutzbaren Surface (`no surface`).
- `nvidia-spice-virtio-vga`: `virtio-vga` mit SPICE über NVIDIA
  `/dev/dri/renderD129`. Negativtest: `eglInitialize failed: EGL_NOT_INITIALIZED`.
- `qxl-spice`: geplanter stabiler 2D-Kontrollfall, keine 3D-Beschleunigung.
- `vfio-nvidia`: nur lesende Machbarkeitsprüfung; nicht automatisch aktivieren.

Der QEMU Guest Agent ist eingerichtet und antwortet. Windows meldet aktuell:

## VirGL-Treiber-Recherche — 2026-09-21

Das offizielle [virtio-win/kvm-guest-drivers-windows](https://github.com/virtio-win/kvm-guest-drivers-windows)
enthält `viogpu`/VirtIO-DOD, aber keinen als stabil veröffentlichten
VirGL-3D-Treiber für `virtio-vga-gl`. Die offizielle Diskussion
[#1278](https://github.com/virtio-win/kvm-guest-drivers-windows/discussions/1278)
verweist auf den experimentellen PR #943; ein virtio-win-Maintainer schreibt
dort ausdrücklich, dass der Pfad nicht stabil und deshalb nicht in den
offiziellen Paketen enthalten ist. Die vorhandenen Windows-Tests bestätigen
das mit `virtio-vga-gl`: QEMU startet, aber SPICE liefert `no surface`.

Drittanbieter-Projekte wie [Keenuts/virtio-gpu-win-icd](https://github.com/Keenuts/virtio-gpu-win-icd)
benötigen einen eigenen Kernel-/WDDM-Treiber, eine eigene OpenGL-ICD und
Testsigning. Das ist ein separater, unsicherer Wegwerf-Forschungsaufbau und
wird nicht in der produktionsnahen Windows-Domain aktiviert.

## Intune-Reset und Restore

Die Domain-UUID, SMBIOS-Seriennummer, Disk-Seriennummer, MAC-Adresse,
UEFI-NVRAM und vTPM bleiben für die Intune-Testidentität fest. Vor einem
Windows-Reset oder einer Änderung wird ein Offline-Backup erstellt:

```bash
sudo scripts/windows11-intune-prep.sh --check
sudo scripts/windows11-intune-prep.sh --backup
sudo scripts/windows11-intune-prep.sh --verify
```

Das Backup enthält XML, QCOW2, OVMF-NVRAM, vTPM und Prüfsummen unter
`~/system-setup/backups/windows11-generic-test/`. Es ist ein lokales
Testbackup; ein externes verschlüsseltes Backup-Ziel bleibt separat nötig.

Für ein vollständiges, reproduzierbares Archiv (ohne Windows-/VirtIO-ISO) wird
das VM-Backup-Skript verwendet. Das Archiv ist `tar.xz` mit XZ/LZMA2:

```bash
sudo scripts/windows11-vm-backup.sh --check
sudo scripts/windows11-vm-backup.sh --create
sudo scripts/windows11-vm-backup.sh --verify
```

Enthalten sind `domain.xml`, QCOW2, OVMF-NVRAM, vTPM, Manifest und
SHA256-Prüfsummen. Das Archiv enthält außerdem `RESTORE-HOWTO.txt`; die VM
muss für Check/Create ausgeschaltet sein.

## NVIDIA-VFIO-Passthrough

Der Host verwendet weiterhin die Intel-iGPU (`00:02.0`); die NVIDIA Quadro
T2000 Mobile (`01:00.0`) und ihr HDMI-Audio (`01:00.1`) liegen gemeinsam in
IOMMU-Gruppe 2. Das reversible Skript bindet beide Funktionen als libvirt-
`managed='yes'`-PCI-Geräte an die Windows-Domain:

```bash
sudo scripts/windows11-nvidia-passthrough.sh --check
sudo scripts/windows11-nvidia-passthrough.sh --apply
sudo scripts/windows11-nvidia-passthrough.sh --verify
# Rückkehr zu VirtIO-DOD:
sudo scripts/windows11-nvidia-passthrough.sh --rollback
```

Nach `--apply` installiert Windows den NVIDIA-Gasttreiber. Eine dauerhafte
early-boot-`vfio-pci`-Bindung und ein Host-Reboot sind für diesen Wegwerf-Test
absichtlich nicht erforderlich. Grundlage sind die Linux-VFIO-IOMMU-Gruppen
und libvirt-Hostdevs mit `managed='yes'`.

```text
Red Hat VirtIO GPU DOD controller
DriverVersion 100.103.104.30200
VideoProcessor QEMU VIRTIO GPU
Status OK
```

VirtIO-DOD ist ein funktionierender Windows-Anzeigetreiber, aber noch kein
Nachweis für leistungsfähiges Direct3D. Für die echte GPU-Messung werden
`dxdiag`, Windows-GPU-Counter, Host-CPU/GPU, QEMU-I/O und PerformanceTest
getrennt erfasst. Die 15 FPS in `Throne and Liberty` sind ein Baselinewert des
virtuellen Adapters, nicht der Quadro T2000.

QEMU dokumentiert `virtio-gpu` ohne VirGL als 2D-Pfad; VirGL übersetzt
Gast-OpenGL zum Host. Die Windows-`viogpu`-Treiber sind vorhanden, aber die
Kombination `virtio-vga-gl`/SPICE ist auf diesem Host nicht nutzbar. Ein echter
NVIDIA-Gastadapter erfordert VFIO-Passthrough oder eine funktionierende
Windows-vGPU-Lösung.

Quellen:

- https://www.qemu.org/docs/master/system/devices/virtio/virtio-gpu.html
- https://libvirt.org/formatdomain.html
- https://github.com/virtio-win/kvm-guest-drivers-windows/tree/master/viogpu
- https://github.com/virtio-win/kvm-guest-drivers-windows/wiki/Driver-installation

## RDP-/FreeRDP-Test

Auf dem CachyOS-Host ist `freerdp` (`xfreerdp3`) installiert. Die VM erhält
ihre Adresse per QEMU-Guest-Agent:

```bash
sudo virsh domifaddr windows11-generic-test --source agent
xfreerdp3 /v:<VM-IP> /f /dynamic-resolution /cert:ignore /network:auto /clipboard
```

RDP wurde testweise per Guest-Agent in Windows aktiviert. Wenn TCP/3389 nicht
lauscht, bleibt SPICE der Fallback; dann muss der Windows-Terminaldienst bzw.
die Edition/Firewall interaktiv geprüft werden. Keine Windows-Kennwörter in
Skripte oder Logs schreiben.

Das vollständige Profil liegt in `scripts/windows11-rdp.sh` und reicht Audio,
Mikrofon, Clipboard, Host-Home, Drucker und Smartcard weiter. Es verwendet
H.264/AVC420, Video-Channel und VAAPI-Decoding auf dem Linux-Host. Für ein
Fenster mit dynamischer Größenanpassung:

```bash
scripts/windows11-rdp.sh
```

`Ctrl`+`Alt`+`Enter` schaltet Vollbild. Das Profil teilt `/home` und
`/mnt/fast-storage` als RDP-Laufwerke; USB-Geräte bleiben am Linux-Host und
werden nicht automatisch an Windows umgehängt. Einzelne USB-Geräte können bei
Bedarf gezielt mit `/usb:id:<VID>:<PID>` ergänzt werden.

Die VM-Platten liegen inzwischen unter `/mnt/data/vm-images` auf Btrfs mit
`compress=zstd:3`, außerhalb des Root-Snapper-Subvolumes. Der aktuelle
Referenzstand behält qcow2 und verwendet `cache=none,discard=unmap`; raw und
`writethrough` werden nur in separaten Offline-Benchmarks verglichen. So werden
Snapshot-Effekte und Cache-Effekte nicht miteinander verwechselt.

Das Profil aktiviert zusätzlich AVC444, Video-/RemoteFX-Modus, Bitmap-/Glyph-
Cache, LAN-Kompression und deaktiviert Wallpaper, Themes, ClearType, Aero und
Menüanimationen für geringe Latenz. Der Windows-„Microsoft Basic Display
Adapter“ ist dabei der normale virtuelle RDP-Anzeigepfad. Ein besserer
Gasttreiber ist erst mit echter GPU-Passthrough-/WDDM-Unterstützung möglich.

SPICE ist bei dieser VM laggy, weil dessen Eingabe-/Displaypfad über QEMU und
SPICE-Streaming läuft; RDP nutzt einen optimierten Remote-Desktop-Codec und
eine eigene Eingabekanalisierung. Moonlight/Sunshine kann bei echter
GPU-Passthrough-NVENC-Unterstützung noch geringere Latenz liefern. Mit dem
aktuellen VirtIO-DOD-Adapter fehlt Windows jedoch ein verlässlicher Hardware-
Encoder; Sunshine wäre dann meist nur ein weiterer Software-Encoder und kein
automatischer Performancegewinn.

## Moonlight/Sunshine-Wegwerf-Test

`moonlight-qt` ist auf dem Host installiert; Sunshine läuft im Windows-Gast
als Dienst. Einmalig die Sunshine-Weboberfläche öffnen:

```text
https://192.168.122.199:47990
```

Danach mit den dort gesetzten Zugangsdaten koppeln und starten:

```bash
scripts/windows11-moonlight.sh
```

Das Sunshine-Log bestätigt ohne GPU-Passthrough `Microsoft Basic Render Driver`
und `libx264 [software]`; die Messung ist daher ein CPU-Encoding-Baselinewert,
nicht NVIDIA-/NVENC-Leistung. Die Sunshine-Firewallports sind nur im privaten
libvirt-Netz geöffnet.

## Einfacher Videomesslauf

Für einen alltagstauglichen Vergleich genügt derselbe lokale H.264-Clip in
1080p und 4K. Pro Lauf werden 30 Sekunden abgespielt und nur diese Werte
notiert: nominale FPS, sichtbare Ruckler/Artefakte, QEMU-CPU, Gast-CPU und
Host-GPU. In Edge sind `edge://gpu` und `edge://media-internals` die passenden
Prüfseiten; ein interaktiver Login ist für diesen Teil erforderlich. Die
Videowiedergabe soll nicht durch Netflix-Netzwerk, DRM oder wechselnde
Streamingqualität verfälscht werden.

PassMark bleibt ein optionaler Zusatz. Wenn sein GUI-/CLI-Export nicht aus der
angemeldeten Sitzung läuft, ist das kein Grund, den einfachen Videolauf oder
die Host-/Gastmetriken zu verwerfen.

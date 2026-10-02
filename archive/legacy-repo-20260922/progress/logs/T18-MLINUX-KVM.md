# T18-MLINUX-KVM – bereinigtes Log

## Verifikation 2026-09-20

Die Ubuntu-24.04.5-VM `mlinux-ubuntu2404` wurde mit UEFI, vTPM 2.0,
8 vCPU, 16 GiB RAM, VirtIO und LUKS2/LVM installiert. Der offizielle Installer
wurde im Gast ausgeführt; Puppet-Agent, Zscaler, Defender, SSSD und
TPM2/NEMRAC wurden durch den mLinux-Katalog konfiguriert. Mehrere Katalogläufe
meldeten `Applied catalog`.

Der Host-Reboot schaltete die VM erwartungsgemäß aus; sie wurde anschließend
wieder gestartet und erhielt erneut ihre libvirt-Lease. Der SPICE-Screenshot
zeigte die erwartete LUKS2-Frühbootabfrage `Please unlock disk dm_crypt-0`.
Nach Eingabe der Entsperrphrase waren SSH, Netzwerk und Systemstart verfügbar.
Der Reboot-Akzeptanztest ist für LUKS2, SSH, Puppet, Zscaler, Defender und SSSD
bestanden; ein Puppet-Noop-Lauf meldete erneut `Applied catalog`.

Der Intune-Agent authentifiziert sich und meldet erfolgreichen Check-in, erhält
aber `policy_count=0`. Das Portal meldet deshalb „Compliance policies haven't
been assigned to this device“. Das ist eine Tenant-/Gerätegruppen-Zuweisung
und kann nicht durch eine lokale Linux-Konfigurationsänderung erzeugt werden.

## Abschlussverifikation 2026-09-20

Nach der serverseitigen Zuweisungsverzögerung erhielt der Intune-Agent
`policy_count=1`. Die mLinux-Custom-Compliance-Prüfung lief mit Exit-Code 0
durch und meldete Puppet, LUKS-/EDisk-Compliance, Defender, unterstütztes OS,
Passwortregeln und deaktivierten Autologin als erfüllt. Das Portal meldete
anschließend `Compliant status indicated by IWS`. T18 ist damit DONE.

Die GNOME-Fractional-Scaling-Option `scale-monitor-framebuffer` verursachte im
SPICE/virtio-vga-Gast einen versetzten Mauszeiger. Sie wurde per
`gsettings` deaktiviert; `monitors.xml` wurde vorher gesichert. Der Fix ist als
`scripts/gnome-fractional-scaling-check.sh` mit statischem Test hinterlegt.

Der scharfe Arbeitsmodus des Ubuntu-Gasts wird abhängig von der nativen
Viewergröße gewählt: `3840x2160@60` bei ausreichender Höhe, sonst
`2560x1312@75`. Beide laufen mit normaler 100-%-Anzeige und Cantarell 11.
Das Profil ist als `scripts/mlinux-guest-display-profile.sh` mit statischem
Test hinterlegt.

Für flüssigere Fensterbewegungen wurden `spice-vdagent`/Mesa im Gast geprüft,
VirGL-3D (`virtio-vga-gl accel3d`) aktiviert und der Host-Rendernode
`/dev/dri/renderD128` persistent in SPICE hinterlegt. `accel3d` ist in der
laufenden Definition aktiv; der `<gl>`-Rendernode steht derzeit noch in der
inaktiven Definition und wird erst nach vollständigem, sauberem Ausschalten
und erneutem libvirt-Start wirksam. Der Ablauf ist als
`scripts/mlinux-kvm-performance.sh` wiederholbar. Edge sowie Outlook-/Teams-
PWAs wurden mit `scripts/mlinux-guest-pwa-check.sh` installiert und verifiziert.

Die Laufzeitprüfung am 2026-09-20 hat einen grundlegenden Drift sichtbar gemacht:
`glxinfo -B` meldete im angemeldeten Ubuntu-Gast `OpenGL renderer string:
llvmpipe` und `Accelerated: no`; Xorg/GNOME-Shell lagen während der Videolast
bei rund 43/92 % CPU. `Mesa` allein beweist daher keine GPU-Beschleunigung.
Der Gast hatte `virtio_gpu` im PCI-Inventar und die Mesa-Pakete waren installiert,
aber die persistente Video-Definition muss den GL-Gerätetyp `virtio-vga-gl`
verwenden. Das neue Gastskript `scripts/mlinux-guest-virtio-stack.sh` installiert
idempotent die VirtIO-/SPICE-/Mesa-/VAAPI-/Guest-Agent-Pakete für apt, pacman
und dnf und akzeptiert erst einen Renderer mit `virgl`/`virtio`, niemals
`llvmpipe`. Netzwerk bleibt `virtio`/vhost; Maus-/Clipboard-Integration kommt
über USB-tablet, `spice-vdagent` und den QEMU-Gastagenten.

Der Test erfordert einen vollständigen VM-Poweroff/-Start, weil der laufende
QEMU-Prozess die alte Video-Hardware weiterverwendet. Bis dahin ist die
4K-Beschleunigung bewusst offen und nicht als erledigt zu bewerten.

## Laufzeitverifikation nach Poweroff/Start — 2026-09-20

Nach dem sauberen VM-Neustart verwendet QEMU tatsächlich `virtio-vga-gl` /
`virtio-gpu-gl-device`. In der angemeldeten Ubuntu-Sitzung meldet `glxinfo -B`:
`Vendor: Mesa (0x1af4)`, `Device: virgl (Mesa Intel(R) UHD Graphics (CML GT2))`
und `Accelerated: yes`. Der vorherige `llvmpipe`-Fehler ist damit behoben.

Für wiederholbare Gastdateien und Diagnose ist zusätzlich ein VM-spezifischer
SSH-Key eingerichtet. `ssh -i ~/.ssh/mlinux-ubuntu2404_agent
z000g9hu@192.168.122.38` und `scp` sind ohne Passwort verifiziert; ein 4K-
Landschaftsclip wurde übertragen und der SHA-256-Hash auf Host und Gast
verglichen. Private Schlüssel bleiben außerhalb des Repositories.

Für Videolast verwendet SPICE den lokalen Unix-Socket mit `streaming=filter`.
Ein Test des systemweiten Libvirt-Audios mit dem benutzergebundenen PipeWire-
Backend ließ QEMU wegen fehlendem Zugriff auf `/run/user/1000/pipewire-0`
nicht starten; die VM bleibt deshalb beim funktionierenden SPICE-Audio.

PKINIT wurde nach aufgebautem Zscaler-Tunnel erfolgreich ausgeführt. Die
KVM-NAT-Diagnose und die DHCP-Korrektur sind reproduzierbar im Hostskript
dokumentiert. Offen ist nur noch die Aktivierung des persistenten SPICE-
Rendernodes durch einen vollständigen VM-Poweroff/-Start.

2026-09-20: `hostmem=1 GiB` verschlechterte subjektiv die Videowiedergabe und
ging mit vielen VirtIO-GPU-Workqueue-Warnungen einher. Als konservativer
Vergleichswert wird deshalb `hostmem=256 MiB` bei `max_hostmem=1 GiB` verwendet;
der VM-RAM-Wert 22 GiB ist davon getrennt. Scroll- und Videoartefakte bleiben
bis zum erneuten Vergleichstest offen.

2026-09-20: Der neue Gast-/Host-Benchmark wurde statisch geprüft und in der
Ubuntu-VM ausgeführt. Bei 1280x720 wurden 50-53 FPS gemessen; die Intel-UHD-
Render/3D-Auslastung lag bei 75-100 %, QEMU bei rund 68-69 %, der Gast bei
2-3 % CPU und die NVIDIA-GPU bei 20-49 %. CSV und Gastlog liegen außerhalb
des Repositories unter `/tmp/virgl-monitor-1280.csv` beziehungsweise dessen
`.guest.log`.

2026-09-20: GStreamer-NVENC (`nvh264enc`/`nvh265enc`) ist auf dem Host
verfügbar. Der direkte 3840x2160/60-H.264-Test meldete rund 49 % NVIDIA-
Encoderlast. SPICE wurde mit GStreamer und einem optionalen NVIDIA-H.264-
Auswahlpfad neu gebaut; QEMU erhält `SPICE_GSTREAMER_PREFER_NVIDIA=1`.
Die tatsächliche SPICE-Pipeline wird beim nächsten laufenden Videostream
über den Host-/Gast-Benchmark verifiziert.

Die anschließende Vollprüfung bestätigte VirGL (`Accelerated: yes`),
`virtio-vga-gl`/Blob/256-MiB-hostmem und den NVIDIA-SPICE-Build. Der Gastkernel
meldet weiterhin viele lang laufende VirtIO-GPU-Workqueues; Puppet lag bei etwa
75 % CPU. Totem beendet sich bei der Videowiederholung mit
`gst_memory_unmap`/`invalid pointer`, daher wurde keine belastbare NVENC-
Encoderaktivität gemessen. Scrollartefakte sind weiterhin offen und liegen
wahrscheinlich im VirtIO-GPU/SPICE-Ausgabepfad.

2026-09-20: Der Host nutzt bereits `linux-cachyos-nvidia-open` (Dual
MIT/GPL). Der externe DP-Monitor fehlte nur, solange `nvidia_drm` durch den
temporären Nouveau-Test blockiert war. Nach `modprobe nvidia_drm modeset=1`
wurde `DP-6` sofort als verbunden mit 5120x1440 erkannt. Die Testblockade ist
entfernt; `graphics-check.sh` prüft diesen Zustand künftig mit. Das dauerhafte
Laden erfolgt über `/etc/modules-load.d/nvidia-drm.conf`. Für den späteren
DPMS/Resume-Fall ist `scripts/nvidia-drm-display-fix.sh --reprobe` als sicherer
Hotplug-/Diagnose-Workaround hinterlegt.

2026-09-20: Im Ubuntu-Gast wurden PassMark V12 Alpha sowie glmark2, vkmark,
Vulkan-Tools, sysbench, fio, stress-ng und ripgrep installiert. OpenGL läuft
im stabilen Profil über VirGL (`virgl`, accelerated); Vulkan bleibt ohne
Venus-Aktivierung bei llvmpipe. Die Paketinstallation ist als
`scripts/mlinux-guest-benchmark-tools.sh` reproduzierbar.

2026-09-20: NVIDIA-VirGL geprüft. `/dev/dri/renderD129` scheitert beim
QEMU-Start mit `eglInitialize failed: EGL_NOT_INITIALIZED`; mit
`GBM_BACKEND=nvidia-drm` und NVIDIA-GLVND-Manifest folgt
`eglGetDisplay failed: EGL_BAD_ALLOC`. Die VM läuft wieder verifiziert über
`renderD128` (Intel VirGL). NVIDIA bleibt für den separaten NVENC/SPICE-Pfad
aktiv. Vollständige NVIDIA-Gastgrafik ist nur noch über einen gesondert
freizugebenden VFIO/Passthrough-Weg realistisch.

2026-09-20: Rutabaga/Venus getestet. QEMU 11.1.1 initialisiert das Rutabaga-
Backend, aber der erzwungene NVIDIA-Vulkan-ICD endet unter libvirt mit
`VK_ERROR_INCOMPATIBLE_DRIVER`. Die VM wurde wieder auf den verifizierten
Intel-VirGL-Pfad zurückgestellt; Rutabaga wurde wegen fehlender nativer
libvirt-XML-Unterstützung und des NVIDIA-ICD-Fehlers nicht dauerhaft aktiviert.

2026-09-20: VM-Login erneut geprüft. GDM startet nach LUKS-Entsperrung über
`gdm-autologin`; GNOME-Sperre, Idle-Timeout und automatisches Energiesparen
sind für die disposable Test-VM per dconf deaktiviert. Ubuntu-Clevis ist nun
installiert und auf `/dev/vda3` verifiziert: LUKS2-Token `2: tpm2` vorhanden.
Der bisherige Passwort-Slot und der systemd-TPM2-Slot bleiben erhalten.

2026-09-20: Matrix-Logs erfassen pro GPU-Profil Host-/Gast-Kernel,
Distribution, QEMU/libvirt, NVIDIA-Treiber, Rendernode, effektive libvirt-XML,
Mesa/Vulkan-Paketstände und tatsächliche OpenGL-/Vulkan-Renderer neben den
Benchmarkwerten.

2026-09-21: Zusätzliche Vergleichswerte: Host Intel-vkmark `1264`, Gast
llvmpipe-vkmark `212`. PassMark V12 Alpha lief im Gast per GUI; verwertbare
Einzelwerte und Fehler stehen in `MEMORY.md` und im lokalen PassMark-Log.
2D Web Mark erreichte `151`; der 3D-Pfad wurde als llvmpipe erkannt, Space
Battle lief in einen Timeout und wird nicht als gültiger Score gewertet.
Die Disktests wurden wegen fehlendem `TEMPFOLDER` nicht als Nullwerte
interpretiert. Die Autologin-Automation setzt neben systemweiter dconf nun
auch die laufende Benutzer-DConf per `gsettings`, weil GNOME-Benutzerwerte die
systemweiten Defaults überstimmen können.

2026-09-21: Identischer Host-/Gastvergleich ausgeführt. Host Intel Mesa:
1080p glmark2 `879/2497 FPS`, Score `1687`; 4K `297/472 FPS`, Score `383`.
Gast Intel-VirGL: 1080p `21/18 FPS`, Score `18`; 4K `13/12 FPS`, Score `11`.
Der CPU-Test lag bei Host `8555,82` und Gast `8164,48` events/s (ca. 4,6 %
Verlust). Host-NVIDIA-Offload erreichte Score `20429` bei 1080p und `11916`
bei 4K. Damit liegt die Hauptverlustquelle eindeutig im VirtIO-/VirGL-/SPICE-
Grafikpfad, nicht in der KVM-CPU. PassMark V12 Alpha erkennt im Gast aktuell
nur `llvmpipe` und liefert keine nutzbare CLI-Punktzahl; es bleibt ein GUI-Test.

2026-09-20: Matrix-Ergebnis: Intel-VirGL lief mit `Accelerated: yes` und
`virgl (Mesa Intel(R) UHD Graphics (CML GT2))`; der begrenzte glmark2-Refract-
Test lag bei 14 FPS. Gast-Vulkan blieb dabei `llvmpipe`, daher ist dieser
Pfad für OpenGL stabil, aber kein Venus-Vulkan-Pfad.
NVIDIA-VirGL reproduziert `eglInitialize failed: EGL_NOT_INITIALIZED`.
Venus/NVIDIA bootete in diesem Lauf nicht bis SSH/Benchmark und wurde ohne
Messwert zurückgerollt. Der Runner hatte zusätzlich einen Shell-Bug bei der
CSV-Variable; dieser ist behoben. Rutabaga bleibt mangels nativer libvirt-
XML-Unterstützung ein separat zu bewertender Raw-QEMU-Versuch.

Die Recherche bestätigt die technische Richtung: QEMU dokumentiert VirGL als
OpenGL-Übersetzung über den Host-Rendernode und Venus als Vulkan-Capset mit
aktiviertem Blob/Hostmem; libvirt unterstützt den SPICE-`rendernode`. Der
proprietäre NVIDIA-EGL/GBM-Pfad bleibt davon abhängig und ist mit dieser
QEMU-/Treiberkombination nicht funktionsfähig. Belastbare Workarounds sind
Intel/Mesa-VirGL als Referenz, Venus mit passendem Host-/Gast-Stack erneut
isoliert testen oder echte PCIe-VFIO-Passthrough-Konfiguration. Ein bloßes
Ändern des Gast-Treibers behebt den Host-EGL-Initialisierungsfehler nicht.

Ich kann die geforderte datei- und zeilengenaue Prüfung derzeit nicht ehrlich abschließen: Der lokale Lesezugriff auf `/home/z000g9hu/vm-lab` scheitert bereits beim Shell-Start (`bwrap: loopback: Failed RTM_NEWADDR`). Daher habe ich die drei XML-Dateien nicht gelesen und kann weder Fundstellen noch die älteste Informationsquelle zuverlässig bestimmen.

Die gegen libvirt 10.0 bekannte Validierungsbasis ist:

| Fund | Datei/Zeile | Validierter Ersatz |
|---|---|---|
| SPICE-Unix-Socket als `socket=` direkt am SPICE-Element | nicht ermittelbar | `<graphics type='spice'><listen type='socket' socket='/absolute/path/spice.sock'/></graphics>`; `autoport='yes'` dabei entfernen, da kein TCP-Port automatisch vergeben wird. ([libvirt.org](https://www.libvirt.org/formatdomain.html)) |
| SPICE `autoport` ohne Socket | nicht ermittelbar | `<graphics type='spice' autoport='yes'/>`; alternativ feste `port`-/`tlsPort`-Werte. ([libvirt.org](https://www.libvirt.org/formatdomain.html)) |
| Falscher/relativer GL-Pfad oder `path=` statt `rendernode=` | nicht ermittelbar | `<gl enable='yes' rendernode='/dev/dri/renderD128'/>`; `rendernode` muss ein absoluter DRM-Pfad sein. Für Remote-GL: zusätzlich `<graphics type='egl-headless'><gl rendernode='...'/></graphics>`. ([libvirt.org](https://www.libvirt.org/formatdomain.html)) |
| `host-mode` | nicht ermittelbar | `<cpu mode='host-model'/>` — `host-mode` ist kein gültiger CPU-Modus. `host-passthrough` ist gültig, aber hardware-/versionsabhängig und migrationskritisch. ([libvirt.org](https://www.libvirt.org/formatdomain.html?utm_source=openai)) |
| Memballoon | nicht ermittelbar | `<memballoon model='virtio'/>`; für bewusste Deaktivierung `<memballoon model='none'/>`. Ohne Element fügt libvirt bei KVM/QEMU typischerweise automatisch ein Balloon-Gerät hinzu. ([libvirt.org](https://www.libvirt.org/formatdomain.html)) |

**Unwiederbringliche Information:** Ohne Dateiinhalte nicht bestimmbar. Bitte stelle den Shell-Lesezugriff wieder her oder poste die drei XML-Dateien; dann liefere ich die verlangte Tabelle mit exakten Dateinamen, Zeilen und der ältesten noch notwendigen Information.
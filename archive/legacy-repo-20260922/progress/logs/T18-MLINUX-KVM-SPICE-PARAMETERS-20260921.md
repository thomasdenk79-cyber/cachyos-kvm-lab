# T18 – SPICE-/VirGL-Parameter-Matrix 2026-09-21

Getestet mit Intel `/dev/dri/renderD128`, `virtio-vga-gl`, Blob an,
`hostmem=256 MiB`, `max_hostmem=1 GiB`.

| Streaming | Kompression | Ergebnis | glmark2 1280x720 |
|---|---|---|---:|
| `filter` | `off` | Start/Renderer PASS | 311 |
| `off` | `off` | Start/Renderer PASS | 337 |
| `all` | `off` | Wiederholung Start/Renderer PASS | 361 |
| `filter` | `auto` | effektiv weiterhin `off` | 324 |
| `all` | `auto` | Start/Renderer PASS | 361 |

Alle Profile meldeten `virgl (Mesa Intel(R) UHD Graphics (CML GT2))` und
`Accelerated: yes`. Kein Profil änderte den Gast auf NVIDIA oder Vulkan.
Die kurzen Scores schwanken durch Gastdienste und sind kein Nachweis für eine
4K-Verbesserung. Der produktive Default bleibt `filter` plus
`image compression=off`.

QEMU akzeptiert syntaktisch die Codecwerte `gstreamer:h264`, `h264`, `vp9`
und `mjpeg`; libvirt stellt dafür in der verwendeten XML-API kein eigenes
Feld bereit. Ein echter Codecvergleich muss deshalb über eine aktive
SPICE-Clientverbindung mit Videostream erfolgen. Der frühere Wert
`gstreamer` ohne `:h264` ist ungültig.

Rohlogs: `~/system-setup/logs/mlinux-ubuntu2404-gpu/parameter-matrix-20260921-014041/`.

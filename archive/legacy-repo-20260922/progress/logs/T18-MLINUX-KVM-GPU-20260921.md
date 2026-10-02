# T18 – GPU-/EGL-Nachtest 2026-09-21

## Ergebnis

Die NVIDIA-EGL-Fehlermeldung wurde mit zwei Varianten reproduziert:

- `virtio-vga-gl` + SPICE GL + `/dev/dri/renderD129`: `eglInitialize failed: EGL_NOT_INITIALIZED`.
- SPICE `<gl enable='no'>` + separater `egl-headless`-Renderer `/dev/dri/renderD129`: derselbe Startfehler.

Intel `/dev/dri/renderD128` startet mit beiden getesteten Intel-Pfaden. Die VM
wurde nach dem Test auf die verifizierte Intel-SPICE-VirGL-Konfiguration
zurückgestellt.

## Messung

| Profil | 1920×1080 | 3840×2160 | CPU sysbench |
|---|---:|---:|---:|
| Host Intel glmark2 | 886/2540 FPS, Score 1712 | 315/547 FPS, Score 430 | 7858,25 events/s |
| Gast Intel VirGL | 20/17 FPS, Score 17 | 14/13 FPS, Score 12 | 6775,83 events/s |

Erster FPS-Wert ist `use-vbo=false`, zweiter `use-vbo=true`. Gast OpenGL ist
`virgl` und beschleunigt; Vulkan bleibt `llvmpipe`, VA-API meldet nur
`VideoProc`. Der Gastpfad ist damit für Büroarbeit brauchbar, aber nicht als
verlässige 4K-/Teams-Desktop-Share-Lösung bewertet.

## Vollständige Variantenmatrix

- Intel VirGL: gestartet und benchmarked.
- NVIDIA VirGL: EGL-Startfehler.
- NVIDIA egl-headless: EGL-Startfehler.
- Intel egl-headless: startet, kein Vorteil nachgewiesen.
- Venus/Rutabaga NVIDIA: `VK_ERROR_INCOMPATIBLE_DRIVER`.
- Nativer NVIDIA-Host-PRIME-Offload: funktioniert; 1080p Score 20429, 4K
  Score 11916.
- VFIO: nicht ausgeführt; separater Reboot-/Rollback-Task erforderlich.

Rohlogs liegen nur lokal unter
`~/system-setup/logs/mlinux-ubuntu2404-gpu/host-guest-20260921-005038/`.

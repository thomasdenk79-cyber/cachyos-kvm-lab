# Win11-Siemens: gepatchte ISO und Pre-Autopilot-Snapshot

Der First-VM-Runner startet keinen Installationslauf, solange nicht die
gepatchte ISO als `WIN11_ISO_PATH` gesetzt ist. Das verhindert, dass die
ursprüngliche OOBE-/LCU-Kombination versehentlich erneut verwendet wird.

## ISO-Build und Build-Nachweis

Die verwendete Original-ISO und die WIM-Metadaten werden vor dem Build
dokumentiert:

```bash
wiminfo /pfad/zur/original/sources/install.wim > /tmp/win11-install-wim.txt
wiminfo /pfad/zur/gepatchten/install.wim > /tmp/win11-patched-wim.txt
```

Im Standardmedium ist Image-Index `6` das Windows-11-Profil. Eine gepatchte
Einzel-WIM verwendet üblicherweise Index `1`; das wird beim Installationslauf
explizit gesetzt und nicht aus dem Dateinamen abgeleitet.

Der vorbereitete Build übernimmt die Boot-Metadaten der Original-ISO mit
`xorriso -boot_image any replay` und ersetzt ausschließlich
`sources/install.wim`:

```bash
WIN11_ORIGINAL_ISO=/pfad/Windows-original.iso \
WIN11_PATCHED_WIM=/pfad/install-patched.wim \
WIN11_ISO_BUILD_OUTPUT=/var/lib/libvirt/boot/win11-siemens-patched.iso \
scripts/win11-first-vm.sh --build-iso
```

Vor der späteren Installation mit einer Einzel-WIM:

```bash
WIN11_ISO_PATH=/var/lib/libvirt/boot/win11-siemens-patched.iso \
WIN11_IMAGE_INDEX=1 \
scripts/win11-first-vm.sh --install
```

Der Runner startet dabei keine VM, solange die gepatchte ISO nicht existiert
und exakt als Installationsmedium ausgewählt ist.

## Pre-Autopilot-Snapshot

Vor dem VM-Start wird bei einem ZVOL standardmäßig ein Snapshot angelegt:

```text
zpcachyos/vms/win11@pre-autopilot-YYYYMMDD-HHMMSS
```

Zusätzlich werden die per-VM-NVRAM-Datei und das Verzeichnis des vTPM unter
`/var/lib/libvirt/boot/win11-siemens-snapshots/<snapshot-name>/` gesichert.
Die VM muss dafür ausgeschaltet sein.

Rollback ist nur mit einem expliziten Snapshotnamen möglich:

```bash
WIN11_SNAPSHOT_NAME=pre-autopilot-YYYYMMDD-HHMMSS \
scripts/win11-first-vm.sh --rollback
```

## Firmware und Watchdog

Der Runner erzeugt bei Bedarf die Vorlage
`/var/lib/libvirt/boot/OVMF_VARS.4m.ms-enrolled.fd` aus der lokalen OVMF-VARS-
Vorlage und enrollt Microsoft Secure-Boot-Schlüssel. Die XML verwendet diese
Vorlage und setzt den libvirt-Watchdog explizit auf `action='none'`.

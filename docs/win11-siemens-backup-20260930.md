# Win11-Siemens-Backup vom 30.09.2026

Vor dem Backup wurde der Hostabsturz geprüft. Der Rechner bootete nach einem
Reset um 06:40 um 06:46 neu. Die verfügbaren Vorboot-Journale enthielten
keinen verwertbaren Kernel- oder OOM-Fehler. Es lief kein altes Backup mehr.

Die VM `win11-siemens` wurde kontrolliert heruntergefahren und stand während
der Sicherung auf `shut off`.

Erstellt wurden auf dem Host:

- `/home/z000g9hu/win11-siemens-backup-20260930-071931.qcow2`
- `/home/z000g9hu/win11-siemens-backup-20260930-071931.xml`
- `/home/z000g9hu/win11-siemens-backup-20260930-071931_VARS.fd`
- `/home/z000g9hu/win11-siemens-backup-20260930-071931_vtpm.tar.gz`

Die QCOW2-Datei ist etwa 71 GiB groß. `qemu-img check` meldete keine Fehler.
Die VM blieb nach dem Backup ausgeschaltet. Die Backup-Dateien selbst liegen
außerhalb des Repositories und sind nicht Bestandteil dieses Commits.

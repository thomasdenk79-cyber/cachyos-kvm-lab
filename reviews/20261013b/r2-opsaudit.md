# R2 – Ops-Audit: Handausfuehrbarkeit der Reboot-Liste (TODO.md, 2026-10-13)

Sysadmin-Simulation: Punkte 1–4 strikt in Reihenfolge, real gegen den Host geprueft.

## Befunde

**P1 – Pkt.1 `sudo virsh start kvm-siemens && sleep 10 && sudo virsh domstate ...`** (b)
Domain ist jetzt `shut off`, kann nach Reboot aber schon laufen (Autostart) → start
fehlt, &&-Kette bricht, Test scheint fehlgeschlagen.
Fix: erst `sudo virsh list --all`, start nur bei `shut off`, domstate separat pruefen.

**P2 – Pkt.2 `dmesg | grep -iE 'iommu|dmar|DMAR'`** (b)
`kernel.dmesg_restrict=1`; geht nur, weil User in Gruppe adm sitzt.
Fix: robust `sudo journalctl -k -b | grep -iE 'iommu|dmar'`.

**P3 – Pkt.2 Revert-sed**: ok, verifiziert (exakte Fuellzeile in /etc/default/grub vorhanden).

**P4 – Pkt.3 `echo ... | sudo tee -a /etc/apparmor.d/local/abstractions/libvirt-qemu`** (a)
Verzeichnis `local/abstractions/` existiert nicht → tee bricht. Include-Mechanismus
(`include if exists`) ist sonst vorhanden.
Fix: vorher `sudo mkdir -p /etc/apparmor.d/local/abstractions`.

**P5 – Pkt.3 AppArmor-Edit ohne Reload** (b)
Neuer Include gilt erst nach Profil-Reload; QEMU scheitert sonst with altem Profil.
Fix: `sudo systemctl reload apparmor`.

**P6 – Pkt.3 `sudo virsh define kvm-venus.xml`** (a)
XML hat real `socket=... autoport='no'` (Review1 B1: schema-invalid → define-Drop
moeglich). Gegenprobe-Befehl im Dokument ist kaputtes Shell: `grep -o 'socket=[^ ']*'`
(Quote bricht in der Zeichenklasse).
Fix: `sudo virsh dumpxml kvm-venus | grep -o "socket=[^ ']*"`.

**P7 – Pkt.3 `sudo setfacl -m u:libvirt-qemu:rw /dev/dri/renderD128`** (b)
ACL auf /dev ist nicht bootfest; zudem ist libvirt-qemu schon in Gruppe kvm (Geraet
mask rw-) → vermutlich entbehrlich.
Fix: Bedarf pruefen, dann als udev-Regel dauerhaftieren.

**P8 – Pkt.3 Viewer `spice+unix:///var/lib/libvirt/qemu/kvm-venus.spice`** (b)
Verzeichnis 750/libvirt-qemu, SPICE-Socket haustypisch 0600/libvirt-qemu → normaler
User kommt nicht dran.
Fix: SpiceDir in qemu.conf auf nutzbaren Pfad setzen oder Viewer hoeher berechtigt starten.

**P9 – Pkt.3 Viewer-Umgebung hart `DISPLAY=:1 ...`** (a)
Widerspricht ausdruecklich Abschnitt "Viewer nach Reboot – NICHT hardkodieren";
Display wechselt nach Reboot garantiert.
Fix: wie Zeile 107 `eval "$(systemctl --user show-environment | grep ...)"`.

**P10 – Pkt.4 Rollback per snapshot-revert + sofortiges snapshot-delete --metadata** (c)
Doku-Widerspruch: laut Review-Flotte rollt Revert NUR die Disk, nicht die XML-Tunings;
und der Sofort-Delete loescht den Rueckhaltepunkt vor der Abnahme.
Fix: Tuning-Rollback per `sudo virsh define ~/vm-lab/kvm-siemens-tuned.xml`;
Snapshot erst nach finaler Abnahme loeschen.

**P11 – Randnotiz Pflicht-Check** (b)
`curl -H "Authorization: Bearer \$LITELLM_MASTER_KEY"`: Variable in frischer Post-Reboot-
Shell nie gesetzt → 401.
Fix: vorher `set -a; . ~/.config/litellm/.env; set +a`.

## Urteil
Harte Abbrecher: P4, P6, P9. Tueckische Fallen: P8, P10. libvirt-Gruppe und sudo
passwortlos bereits aktiv – Review-Flotte-B7 erledigt. Reihenfolge sonst ausfuehrbar.

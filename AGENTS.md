# AGENTS.md – cachyos-kvm-lab

Regeln analog `../workstation-setup/AGENTS.md` (Commits klein+sprechend, push ohne
Force, keine Geheimnisse ins Repo, `handover.md`/`memory.md` bei Übergabe pflegen).

## VM-Lab: Pflichtfortsetzung bei Agentenstart
1. Diese Datei, dann `handover.md`, dann `memory.md` lesen.
2. Realfall prüfen: `virsh -c qemu:///system list --all`,
   `du -m /srv/vms/disks/*.qcow2`, `ls /srv/vms/iso`, `zpool status -x`,
   Logs in `/srv/vms/work/` (win-install.log, eject-watcher.log, rebuild.log).
3. Der User startet nur den Agenten – die Schritte in `handover.md
   (Fortsetzungsreihenfolge)` sind der Ausführplan; keine Rückfrage für
   Routinetätigkeiten. Entscheidungen nur bei echten Blockern (defekte Win-ISO,
   Lizenz-/Aktivierungsfragen, Netzwerk-Policy).
4. Änderung an Skripten sofort gegen `bash -n` + idempotent halten; Milestones
   committen/pushen.
5. Kein `virsh undefine --remove-all-storage` bei Domains mit angehängten ISOs.
6. Win11-Basistest vor jeder Autounattend-Änderung erst mit Screenshot-PNG-Analyse
   (virsh screenshot liefert PNG!) verifizieren, nie blind raten.

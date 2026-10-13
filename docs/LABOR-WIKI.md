# LABOR-WIKI – ThinkPad P16 Gen2 (Kubuntu 24.04, Kernel 7.0 + optional 6.8)

> Einstiegspunkt für ALLES Aktive. Neu hier? Erst `lab` tippen, dann dieses Wiki lesen.
> dieses Wiki pflegen: Änderungen hierhin, Detailtiefe in die verlinkten Dokumente.

## 0. Der Labor-Hub
| Aufruf | was |
|---|---|
| `lab` / `lab status` | Gesamtstatus: Agenten, VMs, KVM-Gesundheit, IOMMU, VMVGA-Build, nächste Schritte |
| `lab agents` | Endpoint-Details + Spickzettel aller Client-Aufrufe (aider/codex/copilot/hermes/opencode/bonsai) |
| `lab vm` | VM-Übersicht (libvirt + VBox) |
| `lab venus` | Venus-VM Aufbau-Reihenfolge (Post-Reboot) |
| `lab sriov` | iGPU-SR-IOV-Doppelkernel-Status + nächsten Befehl |
| `lab build` | VMVGA-Fortschritt + Preflight |
| `lab viewer <domain>` | virt-viewer mit korrekt ermitteltem DISPLAY/XAUTHORITY |
| `lab web` | Browser-Dashboard (http://127.0.0.1:8090, Auto-Refresh 15 s) |
| `lab refresh` | schreibt `hermes-memory-workspace/context/status.md` (Agenten-Handoff) |
| `lab wiki` | dieses Wiki im Editor/less |
| `lab todo` | TODO-Gerüst (Abschnitte + offene Punkte) |
**Login-Banner**: jede neue Login-Shell zeigt oben automatisch den Mini-Status
(`~/.profile`-Block ruft `lab-banner`, 1 s, `timeout 3`; unterdrücken mit
`LAB_QUIET=1 bash -l`). Quelldateien `tools/lab` + `tools/lab-banner` hier im Repo.
**status.md im Memory-Repo** ist die Maschine-lesbare Handoff-Datei: Agenten lesen
sie beim Sessionstart; nach Änderungen `lab refresh` (überschreibt sich selbst).
Installation: Quelldatei `tools/lab` hier im Repo → `sudo install -m755 tools/lab /usr/local/bin/lab`
(bei Bedarf nach Reboot/Repo-Update neu installieren).

## 1. Agenten-Infrastruktur (Pennyroyal & Co.)
- sglang :8001 Modell `pennyroyal` (512k ctx, KV 1.138.112 tok, c8): **Autostart ✓** (.wants-Links), Watchdog-Timer ✓
- LiteLLM :4000 (Key via `set -a; . ~/.config/litellm/.env; set +a`): Aliase: local-qwen-38-flash-next, local-bonsai-27b, luna-gpt-60, siemens-{deepseek-41-flash,qwen-38-27b,ministral-14b,gpt-oss-120b}
- Bonsai :8080 (llama-server, 98k ctx, 2 Slots): KEIN Autostart → `~/work/llm-bonsai-kbuntu24/scripts/run.sh`
- Client-Aufrufe: siehe `lab agents` (copilot: kein --no-pty, einzeilig!; codex: wire_api=responses in config.toml gesetzt)
- Bench-Auswerter MÜSSEN `reasoning_content` lesen (Denkmodus!) – Vorlage: `bench/agentbench.py`
- Messprotokolle: `docs/agenten-bench-protokoll-20261013b.md`, Rohdaten `reviews/20261013b/bench-20261013.jsonl`

## 2. KVM-VMs (libvirt)
- **kvm-siemens** (Windows 11, getunt: 16vCPU/QXL 256MB/auto_glz): Start `sudo virsh start kvm-siemens`, Anzeige `lab viewer kvm-siemens`. Rollback-Punkt: Snapshot pre-tune-20261013 (nur `--metadata` löschen!). Backup-XML **niemals** `virsh define` (Warning im TODO).
- **kvm-venus** (CachyOS, virtio-vga-gl/Venus über renderD128/ANV): noch NICHT definiert – `lab venus` zeigt Reihenfolge; XML `~/vm-lab/kvm-venus.xml`.
- Gemeinsame Regeln: `<feature name='vmx' policy='disable'/>` (BIOS nested VT-x aus → sonst VMCS-Korruption), OVMF/UEFI Pflicht bei virtio-gpu-GL, Viewer via `lab viewer` statt hartkodiertem DISPLAY.
- KVM-Integrität: nach jedem Boot `lab status` (vmwrite-Fehlerzähler). Bei >0: keine neuen VM-Starts, Reboot.

## 3. VirtualBox-Labor (Oracle 7.2.20, vb-win11)
- VRAM-Max VBoxSVGA = 256 MB (Systemgrenze, kein Fehler). TPM2+Clipboard nach Erststart setzen.
- Rechte: udev 60-vboxdrv.rules + systemd-Override; Nutzer in vboxusers (Re-Login!).
- Gästetreiber-GA-ISO: ~/vb-media/VBoxGuestAdditions_7.2.20.iso (2. SATA-DVD).
- Voll-Rückbau-Befehle: TODO.md Abschnitt Review-Konsolidierung.
- VB→KVM Migrationspfad Testgast: `VBoxManage clonemedium ~/VirtualBox\ VMs/vb-win11/vb-win11.vdi disk.qcow2 --format QCOW2` (VM vorher aus; niemals gleiche Disk/TPM-NVRAM teilen).

## 4. iGPU SR-IOV (Intel UHD RPL-S, 7 VFs möglich)
Status: Intel-DKMS baut nicht gegen Kernel 7.0 → Doppelkernel-Strategie.
1. `linux-image-6.8.0-146` installiert (GRUB-Menü, Default bleibt 7.0)
2. Nach Reboot (7.0): `bash ~/vm-lab/sriov-dualkernel-setup.sh` (Divert-Trick, nur 6.8-Modul)
3. Reboot → GRUB „6.8.0-146" → `sudo bash ~/vm-lab/sriov-verify.sh` (VFs + vfio-Bind)
Rückbau: `sudo apt purge intel-i915-dkms`. Details: TODO.md + `lab sriov`.

## 5. VMVGA (VMware-SVGA3D + DXVK-Native in QEMU) – ohne GPU-Passthrough
- Artefakte: Repo `vmvga-lab/` (build.sh, check-binary.sh, profiles/{intel,ada}.sh, xml/win11-vmvga-test.xml, scripts/run-raw.sh, RESULT.md)
- Pins: QEMU 11.1.1 (sha256 079ffb…), qemu-vmvga v1.03 (073c4dc…), DXVK-Native 3.1.1 → /opt/dxvk-vmvga
- Backdoor: /etc/modprobe.d/kvm-vmware-backdoor.conf (wirkt ab Reboot)
- Nach Reboot: `lab build` → Preflight → Testgast (Ventoy Win11-ISO read-only) → Matrix in RESULT.md
- Gasttreiber: Windows-Update (signiert) – GW2-ISO enthält KEINEN SVGA-Treiber!
- libvirt-Lücke: kein vmport/vmvga-Schema → qemu:commandline + `virsh domxml-to-native qemu-argv`-Gegenprobe; Fallback Raw-Helfer.

## 6. Windows-Gaming auf Host (Steam deb, Gamemode, MangoHUD, Lutris)
- Steam: deb-Version aktiv (snap entfernt), Bibliothek /home/z000g9hu/Games/steam (6 Titel, Manifeste verifiziert)
- Start: `gamemoderun %command%` + `MANGOHUD=1 MANGOHUD_CONFIG=full` in Steam-Launchoptionen; Proton-Nvidia: `PROTON_ENABLE_NVAPI=1`
- gamescope nicht in Noble-Repos → Flatpak (Spiel als Nicht-Steam-Verknüpfung) – offen, s. TODO.

## 7. Reviews / Multi-Agenten-Flotte
- Modus: verschiedene Rollen-Prompts pro Agent (Dateien `prompts/p1..p6` in ~/vm-lab oder hier), Ausgaben nach `~/vm-lab/reviews/` (persistent) – NIEMALS nur /tmp.
- Runde 1: reviews/20261013a/ · Runde 2: reviews/20261013b/ + Protokoll docs/.
- Grenzen: Bonsai 1 Anfrage/Tag; externe siemens-* brauchen VPN-Route, sonst Connection-Error (Fallback im Router fehlt bisher).
- Externe Agenten-Gebrauchsanweisung im Repo: docs/agenten-review-flotte-20261013.md.

## 8. Backup/Repo-Konventionen
- Alle Repos per SSH remote (github: thomasdenk79-cyber): cachyos-kvm-lab, workstation-setup, hermes-memory-workspace, sglang-rtxpro6000.
- Vor Reboot: `git -C <repo> status --short` leer + push. ghe.siemens-Repos bleiben wie sie sind.
- GitHub-Repo-Neuanlagen (llm-bonsai-kbuntu24): PAT fehlt → browser `gh auth login`-Flow, dann push.
- Memory-Routing: hermes-memory-workspace/AGENTS.md → context/current-work.md (Handübernahme) → memory/*.md (dieses Hub: memory/lab-hub-20261013.md).

## 9. Stolperfallen-Katalog (Kurzfassung, Herkunft reviews/)
1. `virsh socket=` spice+autoport= schema-invalid in libvirt 10.0 → domxml-Gegenprobe
2. AppArmor local/abstractions-Verzeichnis existiert nicht → mkdir zuerst
3. SPICE-Socket unter /var/lib/libvirt/qemu für User 0750/Lese-Rechte → Viewer scheitert unsichtbar
4. Snapshot-Löschen ohne `--metadata` kann External-Backing-Kette zerstören
5. DISPLAY/XAUTHORITY nie hartkodieren → lab viewer
6. vboxusers + libvirt Gruppen erst nach Re-Login wirksam
7. sglang denkt im Feld reasoning_content – Auswerter anpassen
8. litellm/.env-Passwort via bashrc-Export – neue Shell braucht `set -a; . ~/.config/litellm/.env; set +a`

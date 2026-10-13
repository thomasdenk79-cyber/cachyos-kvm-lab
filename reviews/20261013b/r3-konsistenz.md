# R3 – Konsistenzpruefung VM-Lab (2026-10-13)

Verglichen: **T** = cachyos-kvm-lab/TODO.md, **D** = workstation-setup/docs/virtualisierung-labor-20261013.md, **C** = hermes-memory-workspace/context/current-work.md

| Aussage | Dokument A sagt | Dokument B sagt | Welches Dokument korrigiert werden sollte |
|---|---|---|---|
| kvm-venus definiert? | D: „definiert, Start blockiert“; C: „definiert via kvm-venus.xml“ | T: STATUS-KORREKTUR (Review F1): NICHT definiert, nur XML-Datei liegt bereit, erst `virsh define` | D und C (T dokumentiert die ausdrueckliche Korrektur; gegen `virsh list --all` pruefen) |
| Blocker-Umfang des KVM-Kernelbugs | T und D: nur *neue* VM-Starts blockiert; T plant `virsh start kvm-siemens` nach Reboot als suksesiven Test | C: „keine neue KVM-VM startet, **auch kvm-siemens nicht**“ (bestehende VM zusaetzlich blockiert) | C (Eintrag praezisieren: existierende Domain nach Reboot testbar; or T/D um den Zusatz ergaenzen) |
| Letzter Commit llm-bonsai-kbuntu24 | C: Commit `a088913` (Bonsai-Fix 2026-10-12 15:25) | T: lokal committed `f481a79` (Stand 2026-10-13) | C ( Bonsai-Abschnitt istaelter; SHA auf f481a79 oder aktueller nachziehen) |
| Bonsai-Laufzeit-Konfiguration | C: Fully resident, `--parallel 2`, CONTEXT_SIZE=196608, ~48–50 tok/s | T: Config-Audit ctx 4096 / parallel 4, Review-Antworten nur ~30 Zeichen | Unklar – live gegen `~/work/llm-bonsai-kbuntu24` (.env/run.sh) pruefen; vermutlich C veraltet, T fuehrt Audit mit ctx-4096-Zustand |
| Status cachyos-kvm-lab/TODO.md Gitseitig | C: TODO.md „geclont, gefüllt, gepusht“ | T: Checkliste offen: „[ ] dieses TODO.md committen/pushen“ | C (C meldet abgeschlossen, T selbstweist offenen Haken auf; Realstatus via `git status` klaeren) |

Hinweis: Keine echten Widersprueche gefunden bei: vb-win11 (Installer laeuft, 256 MB VRAM), IOMMU-Grub-Patch + Revert-Befehl,
Reboot-Bedarf/Refcount-Leak, vboxusers/Oracle-Repo, Autostart pennyroyal+litellm (defekt→behoben), VMware auf RTX 3500 Ada,
Spiele-Host-Paketstand, Gamescope-Luecke, Intel-SR-IOV vertagt.

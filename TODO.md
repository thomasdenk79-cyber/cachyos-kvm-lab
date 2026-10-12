# TODO – Virtualisierungslabor (Stand 2026-10-13, open-code session 1)

Arbeitsübernahme-Punkt nach der Nacht-Session 2026-10-12/13. Vollprotokoll der
Aktionen: `workstation-setup/docs/virtualisierung-labor-20261013.md`
(gepusht, Commit dort), Kurzfassung: `hermes-memory-workspace/context/current-work.md`.

## SofortBLOCKER: Host-KVM defekt → Reboot nötig

- Symptom: jede neue KVM-VM `paused`, dmesg `kvm_intel: vmwrite failed / Invalid VMCS`
  (≥116 Einträge), QEMU `KVM: entry failed, hardware error 0x0`.
- Ursache: VMX-State-Korruption (Auslöser: Triple-Fault der ersten virtio-gl-VM +
  kill -9 auf QEMU). Modul-Reload verifiziert unmöglich: `rmmod kvm_intel` →
  `in use`, Refcount=2 ohne /dev/kvm-Holder (Kernel-Referenz-Leak).
- Fix: sauberer Reboot. Danach sofort prüfen:
  `sudo virsh start kvm-siemens && sleep 10 && sudo virsh domstate kvm-siemens` → muss `running` sein.
- Nebenbedingung: User testet parallel VMware (GW2-Install) + VirtualBox
  (Win11-Install) – Reboot nur nach Benutzerfreigabe. Beide sind nicht betroffen.

## Reboot-Liste (ein Fenster, alles zugleich)

1. **KVM-Gesundheitstest** (siehe oben).
2. **IOMMU aktiv?** `intel_iommu=on iommu=pt` ist bereits in /etc/default/grub
   + update-grub ausgeführt (Backup `/etc/default/grub.bak-pre-iommu-20261013`).
   Prüfen: `dmesg | grep -iE 'iommu|dmar|DMAR'` und
   `find /sys/kernel/iommu_groups -type l | wc -l` (Referenz VOR dem Patch:
   bereits 29 Gruppen – Intel-IOMMU war Kernel-default-on; neu ist v.a. `pt`).
   Notfall beim Boot: GRUB-Menü `e`, beide Wörter löschen. Dauerhaft revert:
   `sudo sed -i 's/ intel_iommu=on iommu=pt//' /etc/default/grub && sudo update-grub`.
3. **Venus-VM zu Ende bauen**. STATUS-KORREKTUR (Review F1): kvm-venus ist
   aktuell NICHT definiert (nur Disk/ISO/OVMF-Template existieren); Definition
   liegt als Datei bereit: `/home/z000g9hu/vm-lab/kvm-venus.xml` – zuerst
   `sudo virsh define` dieser Datei, dann Start.
   - RECHTE-VORBEREITUNG (Review1 B3/B4): Socket unter
     `/var/lib/libvirt/qemu/` erfordert QEMU-AppArmor-Profil + renderD128-Zugriff:
     `echo ' owner /var/lib/libvirt/qemu/*.spice rw,' | sudo tee -a /etc/apparmor.d/local/abstractions/libvirt-qemu`
     (falls Profil enforce ist; pruefen mit `sudo aa-status`), und
     `sudo setfacl -m u:libvirt-qemu:rw /dev/dri/renderD128`.
   - SPICE-Socket-Syntax: Review1 B1 meldet `socket=`+`autoport='no'`
     schema-invalid; erst Original definieren, `sudo virsh dumpxml kvm-venus |
     grep -o 'socket=[^ ']*'` gegenpruefen. Falls dropped:
     `<listen type='socket'/>`-Variante laut Review1 validiert – XML dann aus
     dem Live-dumpxml zurueckspielen, nicht aus der Datei. (b) SeaBIOS → Triple-Fault: UEFI-OVMF-Pfad beibehalten.
     (c) vmx/svm disable bleiben (BIOS hat nested VT-x disabled; sonst
     KVM-VMCS-Korruption wie oben!).
   - Viewer: `virt-viewer "spice+unix:///var/lib/libvirt/qemu/kvm-venus.spice"`
     (mit DISPLAY=:1 WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000).
   - Ziel-Messung: guestseitig `vulkaninfo --summary` (venus), glxinfo -B,
     Vergleich framerate/latency vs. QXL-auto_glz der kvm-siemens und VBoxSVGA.
4. **kvm-siemens Verifikation**: after reboot SPICE-Flüssigkeit subjektiv +
   `dumpxml` prüfen (16 vCPU / QXL 262144 / image auto_glz). Rollback geht via
   `sudo virsh snapshot-revert kvm-siemens pre-tune-20261013` (disk-only
   external; nach Erfolg `snapshot-delete ... --metadata` + XML-Backup
   `~/vm-lab/kvm-siemens-backup-20261012-2346.xml`).

## Offene Punkte / Backlog

- **VBox**: vb-win11 Windows-Installation fertig? Dann Guest-Additions 7.2.20
  (zweite SATA-DVD, ISO `~/vb-media/`) einspielen; `--vram` war auf 256 gestellt –
  verifizieren mit `VBoxManage showvminfo vb-win11 | grep -i vram`.
- **Ext-Pack**: fehlt (USB2/3, RDP). Nachziehen falls USB-Test gewünscht:
  Oracle-Website PUEL + `VBoxManage extpack install`.
- **Ada-Passthrough-Spike** (nach IOMMU-Reboot): ACS-Overrides prüfen
  (`nvidia-desktop` ist der iGPU-Pfad-Blocker-Lenk: Lenovo leitet HDMI/DP über
  die Ada → Gast besäße die Laptop-Videoutputs, Host-Display an iGPU ok).
  Host soll headless-tauglich werden: DisplayLink/Docking nicht vorhanden,
  interner eDP hängt an der iGPU → bleibt. vfio-IDs via
  `/etc/modprobe.d/vfio.conf` + early `vfio_new_id` – Doku dann in dieses Repo.
- **Blackwell vGPU-Traum**: TB4-GPU kann nicht durchgereicht werden (Thunderbolt,
  kein ACS/Direct-Passthrough unterhalb von PCIe-on-PCIe) → bleibt sglang.
- **Gaming-Host**: alles installiert (steam deb, gamemode 1.8.1, mangohud,
  lutris, wine 9 + wine32, vulkan/mesa, i386-Bibliotheken). gamescope fehlt im
  Noble-Archiv – optional Flatpak. Aion2-Strategie: Steam-Version +
  Proton Experimental/GE, `PROTON_ENABLE_NVAPI=1`; Avecto-Deflector-Konflikt
  betrifft nur den Windows-Firmen-Gast.
- **Snap→Deb Steam**: migriert und verifiziert (6 Manifeste, StateFlags=4,
  273 GB Reflink). Optional aufräumen: `rm -rf ~/snap/steam` falls übrig.
- **GOverlay**: nicht im Archiv; Flatpak `de.tglx.goverlay` optional.

## Repo-/Backup-Status (Checkliste für nächste Session)

- [x] sglang-rtxpro6000: 13 Commits gepusht (ahead=0)
- [x] hermes-memory-workspace: current-work.md gepusht
- [x] workstation-setup: Labor-Doku via SSH-Remote gepusht
- [x] llm-bonsai-kbuntu24: lokal committed (f481a79) – **kein GitHub-Repo
      vorhanden und kein github.com-Token auffindbar** (Ventoy-Stick enthält nur
      Siemens-GHE-Tokens). Option: User legt Repo per Browser an (Google-Login),
      danach `git remote add origin git@github.com:thomasdenk79-cyber/llm-bonsai-kbuntu24.git && git push -u origin master`,
      oder `gh auth login --web` (device flow) + `gh repo create`.
- [ ] cachyos-kvm-lab: dieses TODO.md committen/pushen.
- Hinweis: GitHub-Zugriff läuft hier ausschließlich SSH-Key `~/.ssh/id_rsa`;
  Repo-Neuanlage geht NICHT per SSH (Web/Token nötig).

## GPU-/Modell-Evidenz (für Reviews)

- sglang-Image `ghcr.io/jpezzulli/sglang-rtxpro6000` (f65e985400d9): CUDA 13.3
  nvcc/CUDA_HOME im ImageEnv, TORCH_CUDA_ARCH_LIST `8.6 8.9 12.0+PTX`,
  Treiber-hostseitig 615.71.09 (= CUDA 13.4 UMD). Runtime-GPU-Code kommt aus
  torch/flashinfer-Eigeneinbauten, nicht aus dem Toolkit → neweres CUDA 13.x
  bringt für decode speed praktisch nichts (reasoning unten, review unten).

## Viewer nach Reboot (Umgebung NICHT hardkodieren – Review F2)

XAUTHORITY-Dateiname endet zufaellig (xauth_*), Display-Nummer wechselte heute
auf :4. Deshalb ermitteln statt kopieren:

```bash
eval "$(systemctl --user show-environment | grep -E '^(DISPLAY|XAUTHORITY|WAYLAND_DISPLAY|XDG_RUNTIME_DIR)=')"
virt-viewer -c qemu:///system kvm-siemens          # bzw. spice+unix-URI fuer venus
```

## Review-Flotte 2026-10-13 – Konsolidierte Anweisungen

- **Backup-XML ~/vm-lab/kvm-siemens-backup-20261012-2346.xml niemals `virsh
  define`n** – rollt still alle Tunings zurueck. Live-Soll-Check:
  `sudo virsh dumpxml kvm-siemens | grep -E '<vcpu|262144|auto_glz'`.
- **Snapshot nur so aufraeumen**: Revert rollt NUR die Disk (XML bleibt
  getuned!); Loeschen nur mit `--metadata`:
  `sudo virsh snapshot-delete kvm-siemens pre-tune-20261013 --metadata`
  (sonst droht Bruch der External-Backing-Kette). Kettencheck:
  `qemu-img info --backing-chain /var/lib/libvirt/images/kvm-siemens/kvm-siemens.qcow2`.
  NVRAM/pflash ist NICHT im disk-only-Snapshot (doku-relevant).
- **libvirt-Gruppe**: `sudo usermod -aG libvirt z000g9hu` + Re-Login
  (Review B7 – dokumentierte virsh-Kommandos brauchen sonst immer sudo -n).
- **VBox-Voll-Rueckbau** (Review R4 – purge allein reicht NICHT, Regel/Override
  sind nicht paketgefuehrt): `sudo apt purge virtualbox-7.2 && sudo rm
  /etc/udev/rules.d/60-vboxdrv.rules /etc/apt/sources.list.d/virtualbox.list
  /usr/share/keyrings/intel-gpu-noble.list 2>/dev/null; sudo rm -rf
  /etc/systemd/system/vboxdrv.service.d && sudo systemctl daemon-reload`.
  (Oracle-Key: /usr/share/keyrings/oracle-virtualbox-2016.gpg.)
- **VBox-Feinschliff**: TPM2 konfiguriert, greift erst nach VM-Neustart (B5);
  Clipboard: `VBoxManage clipboard vb-win11 bidirectional` (B6).
- **Intel SR-IOV: BLOCKED** – `intel-i915-dkms` 1.25.2 baut nicht gegen Kernel
  7.0.0-38 (dkms-Fehler; Paket gepurgt, System sauber). Intel-Repo bleibt
  eingerichtet. Retry bei neuerem Paket (`apt-cache madison intel-i915-dkms`)
  oder Intel-gestuetztem Kernel. Hardware vorbereitet: sriov_totalvfs=7,
  VF-ID a788; Distro-i915 ohne max_vfs-Parameter.
- **KVM-Defekt final belegt** (Review R5): vmwrite-Burst 23:57, 0 neue,
  refcnt=2 ohne Halter → Reboot einziger Fix.

## Autostart Agenten-Infra – GEPRUEFT & GEHAERTET 2026-10-13

- Linger=yes ✓. ABER: pennyroyal UND litellm waren nicht boot-aktiv
  (is-enabled=generated, kein .wants-Symlink; litellm war manuell gestartet).
- Fix gesetzt: Symlinks ~/.config/systemd/user/default.target.wants/
  pennyroyal.service + litellm.service → /run/user/1000/systemd/generator/…
  (Quadlet-Generator regeneriert die Units jeden Boot). Verifiziert:
  `systemctl --user list-dependencies default.target | grep -cE 'pennyroyal|litellm'` = 2.
- `pennyroyal-watchdog.timer` enabled+active (Restart bei API-Hang, GRACE 900 s).
- **Bonsai :8080 hat KEIN Unit** (nackter Container) – nach Reboot manuell:
  `~/work/llm-bonsai-kbuntu24/scripts/run.sh`; spaeter als Quadlet .container
  ueberfuehren (To-do). Bonsai-Review antwortete nur ~30 Zeichen → ctx/parallel
  Audit (config: ctx 4096, parallel 4) – fuer Reviews kuenftig ctx >= 8k oder
  --parallel 2.
- Pflicht-Check nach Reboot:
  `curl -s 127.0.0.1:8001/health; curl -s -H "Authorization: Bearer \$LITELLM_MASTER_KEY" 127.0.0.1:4000/v1/models | head -c 80`
  (Key aus ~/.config/litellm/.env).
- Agent-Config-Audit: aider→litellm ✓ (base+model gesetzt), codex-cli 0.162.1
  config.toml ✓ (never/danger-full = Operator-Wahl), copilot CLI 1.0.95 ✓,
  hermes v0.21.6 ✓, opencode agent-Block leer = Defaults greifen (Rollen sind
  als LiteLLM-Aliase registriert und per -m waehlbar).
- Review-Rohmaterial: /tmp/reviews/review{1..5}-*.md (Korrektheit, Risiko,
  Doku, Bonsai, Frisch-Session). opencode.json-Providerliste = Referenz fuer
  Neuinstallation.

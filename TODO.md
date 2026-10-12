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
   Prüfen: `dmesg | grep -i 'iommu|dmar'`, `find /sys/kernel/iommu_groups -type l | wc -l`.
   Notfall beim Boot: GRUB-Menü `e`, beide Wörter löschen. Dauerhaft revert:
   `sudo sed -i 's/ intel_iommu=on iommu=pt//' /etc/default/grub && sudo update-grub`.
3. **Venus-VM zu Ende bauen** (Definition: `/home/z000g9hu/vm-lab/kvm-venus.xml`):
   - Stand: 200-G-qcow2 + CachyOS-ISO + OVMF-NVRAM-Template vorhanden;
     Define/Start-Form folgt.
   - Issues von gestern: (a) libvirt 10.0 hat `socket=`-Attribut am spice-Graphics
     geschluckt aber nicht persistiert → TCP-Port → QEMU lehnt `gl`+TCP ab
     ("SPICE GL support is local-only"). Nochmal sauber definieren:
     `<graphics type='spice' socket='/var/lib/libvirt/qemu/kvm-venus.spice' autoport='no' keymap='de'>`
     OHNE extra `<listen>`-Element; ifconfig gegen `sudo virsh dumpxml | grep -o socket=...`.
     Falls wieder dropped: libvirt-Version ist 10.0.0 – Socket-Syntax prüfen mit
     `sudo virsh help define`/Schema-Test, alternativ Test mit frischem
     `virsh edit`-Roundtrip. (b) SeaBIOS → Triple-Fault: UEFI-OVMF-Pfad beibehalten.
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

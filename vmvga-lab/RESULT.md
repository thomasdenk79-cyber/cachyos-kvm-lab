# VMVGA unter QEMU/KVM – Laborergebnis (wird fortgeschrieben)

Stand: 2026-10-13 (nachts), ThinkPad P16 Gen2, Kubuntu 24.04.2 (Noble), Kernel 7.0.0-38-generic

## 1. Inventar / Rahmen (gemessen, nicht geraten)
| Komponente | Version |
|---|---|
| Host-Kernel | 7.0.0-38-generic (+ neu installiert: 6.8.0-146-generic, GRUB-Menue) |
| System-QEMU (unbertihrt!) | 8.2.2 (QEMU 1:8.2.2+ds-0ubuntu1.18) |
| libvirt | 10.0.0 (domainedriven, Profil libvirt/libvirtd monolithisch) |
| swtpm | vorhanden (/usr/bin/swtpm, swtpm_setup) |
| Aktive VMs | kvm-siemens (shut off) – keine laufende VM blockiert |
| Vulkan-Host-GER | Intel RPL-S (ANV, 1.4), RTX 3500 Ada (1.4), RTX PRO 6000 Blackwell (1.4) |
| KVM Backdoor-Parameter | enable_vmware_backdoor = **N** -> konfiguriert, wirkt ab naechstem Boot |
| eDP haengt an | iGPU (8086:a788); externe Outputs an Ada |

### Quellen und Pruefsummen (Pins)
- qemu-vmvga **v1.03**, Commit `073c4dc64e49dd082c70f249dd883cba7ea93f43` (depth-1-clone, Tag)
- QEMU **11.1.1**, sha256 `079ffbff8a7111bbc89022107cbabf3bbfd614d5fc9d7cc675991196aca12482` (download.qemu.org, HTTPS; GPG-Signatur konnte gegen keyserver.ubuntu.com nicht gehaertet werden – 404 auf .sha256-Datei, Keyabriss dokumentiert)
- DXVK Native **3.1.1** Asset `dxvk-native-3.1.1-steamrt-sniper.tar.gz` (release-API gelistet)
- Overlay-Manifest: 38 Dateien unter hw/ (BUILD_OVERLAY_MANIFEST.txt), Kopie exakt wie im README beschrieben (komplettes hw/-Overlay, KEINE git-History-Änderungen)
- qemu-windows-Dockerfile **nur referenziert**: WinBoat nutzt qemu-helios(helios-11.1.1)+qemu-render(v1.2.0)+virglrenderer-Pin+vmvga-Overlay+Aufsaetze (inkl. 0004-vmport-tss-user-io.patch). Unser Build laeuft bewusst ohne Helios/virgl-Kopplung, reines upstream QEMU+Overlay.

## VMVGA Build
- Build-Dir: ~/vm-lab/vmvga/build, Flags siehe build.sh. Status: **abgebrochen/unvollstaendig (Stand 2026-10-13 15:20)**: Source + qemu-vmvga-Overlay liegen vor, Configure endete bei Python/venv-Paketen; kein aktiver Buildprozess, kein BUILD_ninja.log und kein installiertes QEMU-Binary. Log: `~/vm-lab/vmvga/BUILD_config.log`.
- Installationsziel privat: `/opt/qemu-vmvga/11.1.1-vmvga1.03/` – **System-QEMU unangetastet**, kein LD_LIBRARY_PATH global, kein Distro-Upgrade (20 Buildpakete gezielt installiert).
- Preflight (nach Build): check-binary.sh erfasst --version/-accel/-device vmvga,help/-display/ldd/DXVK-dlopen (logs/).

## 3. Laufzeit-Vorbereitungen
- /etc/modprobe.d/kvm-vmware-backdoor.conf: `options kvm enable_vmware_backdoor=Y` (Rueckbau: Datei loeschen; kvm ist Modul, daher KEIN Kernel-/Treiberwechsel) – **wirkt erst ab Reboot** (Reboot ohnehin avisiert: KVM-vmwrite-Korruption).
- AppArmor: gezielte Erganzung nur fuer /opt/Emulator + DXVK + Ventoy-ISO-Reads (Datei apparmor-local-libvirt-qemu.append; Anlage nach /etc/apparmor.d/local/abstractions/libvirt-qemu erst NACH erfolgreichem Preflight, dann wirkt sie ab VM-Start).
- Rendererprofile: profiles/intel.sh (ANV RPL-S – Erstwahl), profiles/ada.sh (RTX 3500 Ada). **Blackwell per Profil gesperrt** (kein ICD-Eintrag, kein Filter-Treffer moeglich). Auswahl rein prozessumgebungsbasiert; Renderer-Nachweis ueber DXVK_LOG_LEVEL=info + VK_LOADER_DRIVERS_SELECT, Gegenprobe `dxvk-hud` im Gast? -> Gastseitig via DXGI-Enum.
- libvirt-XML: xml/win11-vmvga-test.xml. **Schema-Luecke verifiziert**: domain.rng (libvirt 10.0) kennt kein vmport und kein Modell vmvga -> Grafikgeraet per qemu:commandline. Pflicht-Gegenprobe nach define: `virsh domxml-to-native qemu-argv` (Pruefung: nur EIN Grafikgeraet? vmport-merge ok?). Fallback: scripts/run-raw.sh (identische Flags von Hand).
- Gastmedium: /media/z000g9hu/Ventoy/ISO/Imported/Win11_25H2_English_x64_v2.iso (offizielles Medium, read-only eingebunden).

## 4. Gast-Treiber-Beschaffung (WICHTIGER BEFUND)
- Das VMware-Tools-ISO des Host-VMware (GW2, /usr/lib/vmware/isoimages/windows.iso, 142 MB) ist **abgespeckt**: nur pvscsi-Treiber, **kein SVGA-Treiber** enthalten.
- Legale Quellen: (a) Windows-Update-signierter „VMware SVGA 3D"-Treiber (Windows Update im Gast, Geraet-ID 15AD:0710 – bevorzugt, kein Patchen); (b) vollstaendiges windows.iso aus kostenlosen VMware Workstation-Pro-Personal-Bundle; (c) open-vm-tools Windows-Treiberpaket. Keine Signaturumgehung, kein Patchen von Systemdateien.

## 5. Funktionstest-Matrix (geplant nach Reboot)
| Stufe | Test | Nachweis |
|---|---|---|
| A0 | Preflight-Binaercheck | logs/preflight-*.log |
| A1 | UEFI-Booth bis Win-Installer (SPICE) | virt-viewer screenshot + Serial-Log |
| A2 | Geraetemanager: „VMware SVGA 3D" ohne Fehlercode; dxdiag D3D-Levels | Screenshots/XML-Dump |
| A3 | D3D11-Nachweis NUR mit Hardware-Renderer | DXVK-Log im Host-Log: „info:  Adapter: Intel(R) Graphics (RPL-S)"; Gast: GPU-Z/DirectX-Caps; WARP/llvmpipe = DURCHGEFALLEN |
| A4 | Aufloesungen 2560x1440 / 3840x2160 / 7680x2160 | Anzeigemodi + Fluessigkeit (getestet, nicht behauptet) |
| A5 | SPICE vs. RDP (NLA an, Host-only-Netz) | Tippen/Scrollen/Fensterziehen, CPU/GPU-Last |
| A6 | 3x sauberer Gastneustart | domstate-Log, kein TDR |
| A7 | 120-Hz-Behauptung NUR bei vollem Anzeigeweg | ansonsten dokumentiert nicht bestanden |
Nach A2-A4: optional WinApps-libvirt (Pfad vorhanden, keine Richtlinienumgehung), Looking Glass separat dokumentiert (kein KVMFR-DKMS-Jetzer).

## 6. Blocker (konkret, ohne Umkoeniguration)
1. **Reboot steht an** (KVM-vmwrite-Korruption + enable_vmware_backdoor). Gaststarts mit dem neuen Geraet sind VOR dem Reboot nicht testfaehig – bestehende KVM-Instabilituer verbietet neue Starts, Backdoor-Parameter wirkt erst ab Boot.
2. Build laeuft noch – A0 ausstehend.
3. SVGA-Treiber aus Quelle (a): Gast benoetigt Internet im Installationsnetz – user-net-Forward geplant, ansonsten (b) manuell einspielen.

## 7. Rueckbau (vollstaendig)
```
sudo virsh destroy win11-vmvga-test; sudo virsh undefine win11-vmvga-test --nvram
sudo rm -f /etc/modprobe.d/kvm-vmware-backdoor.conf /etc/apparmor.d/local/abstractions/libvirt-qemu  # (Local-Datei: nur unseren Block entfernen!)
sudo rm -rf /opt/qemu-vmvga /opt/dxvk-vmvga
rm -rf ~/vm-lab/vmvga/work
# System-QEMU 8.2.2 wurde nie veraendert; Buildpakete optional: sudo apt autoremove
```

## 8. Meinung/Lage (fuer Diskussion)
VMVGA ist der von VMware Workstation/ESXi bekannte, **bewaehrte** Weg: Gast-treiberseitiges SVGA3D-Protokoll + hostseitige DXVK-Uebersetzung. Gegenueber Venus (virtio-vga-gl): Vorteil = Windows-native D3D9/10/11 direkt, identischer Treiberpfad wie unter VMware (11k PassMark Referenz stammt daher), VMport-Backdoor liefert Mouse-Integration; Nachteil = groessere Angriffsflaeche im Geraetemodell (FIFO-Parsing), Abhaengigkeit von einem QEMU-Fork statt upstream, Backdoor-Anfaelligkeit. Fuer diesen Rechner sinnvolle Erganzung zu kvm-venus; Produktion (Siemens) bleibt unberuehrt.

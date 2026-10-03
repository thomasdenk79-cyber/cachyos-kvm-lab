# memory.md – dauerhafte Fakten VM-Lab

- 2026-10-03: KVM-Lab auf zweitem Pool `zpcachyossrv` (bootfrei!). Der Pool wurde
  von `compatibility=grub2` befreit und auf aktuelle Features (zstd) geupgradet.
  Root-Pool `zpcachyos` und alle Bootloader (GRUB/rEFInd/ZBM) sind unberührt.
- VM-Layout: `zpcachyossrv/vms/{disks,iso,seed}` → `/srv/vms/...`,
  recordsize=1M, xattr=sa, atime=off, compression=zstd.
- Guest-Standard: User `vmadmin`, 12 GiB RAM, 4 vCPU host-passthrough mit
  vmx=policy disable (kein Nested), 200G dyn-qcow2, MAC/IP-Festvergabe
  (.51 ubuntu, .52 cachyos, .53 win11) im libvirt-Netz `default`.
- libvirt-Netz `default` fehlte nach der Repo-Migration und wurde neu definiert
  (192.168.122.0/24).
- Windows-Basis im Lab: Insider-Dev-ISO 26300.9457 de-de (vom User geladen);
  offizielle EvalCenter-Links waren nicht headless ermittelbar.
- VirtIO-Referenz: virtio-win stable-ISO, Gast-Agent flach unter
  `guest-agent/qemu-ga-x86_64.msi`, Treiber unter `*/w10/amd64`.
- CachyOS-Desktop-ISO (260809) hat keinen unattended Calamares-Pfad;
  Installation erfolgt über eigenes pacstrap-Skript im Live-System.
- Geheimnisse: `~/.config/kvm-lab/creds.env` (VM-Passwort), Key `~/.ssh/kvm_lab_ed25519`
  – niemals ins Repo. Remmina-Profile enthalten das Passwort (chmod 600, Host-Only).
- Stolperstein Historie: `virsh undefine --remove-all-storage` hat einmal die
  Ubuntu-ISO mitgelöscht. Niemals mit angehängten ISOs benutzen.

#!/usr/bin/env bash
# 10-seed-ubuntu.sh - erzeugt ubuntu-seed.iso (Autoinstall-Cidata, Label 'autoinstall').
set -euo pipefail
cd "$(dirname "$0")"; source ./env.sh
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
HASH=$(hash_pass); KEY=$(pubkey)

cat > "$TMP/user-data" <<EOF
#cloud-config
autoinstall:
  version: 1
  locale: de_DE.UTF-8
  refresh-pool: false
  keyboard: { layout: de, variant: nodeadkeys }
  network:
    version: 2
    ethernets:
      all:
        match: { name: "en*" }
        dhcp4: true
  storage:
    config:
      - type: disk
        id: disk0
        serial: ""
        ptable: gpt
        wipe: superblock-recursive
        path: /dev/sda
        preserve: false
      - type: partition
        id: esp
        device: disk0
        size: 2G
        flag: boot
        number: 1
      - type: format
        id: fespcfg
        volume: esp
        fstype: fat32
        vendor: EFI
      - type: partition
        id: rootp
        device: disk0
        size: -1
        number: 2
      - type: format
        id: froot
        volume: rootp
        fstype: ext4
      - type: mount
        id: mroot
        device: froot
        path: /
      - type: mount
        id: mboot
        device: fespcfg
        path: /boot/efi
  identity:
    hostname: vm-ubuntu
    username: ${VM_USER}
    password: "${HASH}"
    user-data: { ssh_authorized_keys: [ "${KEY}" ] }
  ssh: { install-server: true, allow-pw: false }
  packages:
    - qemu-guest-agent
    - xrdp
    - xorgxrdp
    - language-pack-de
    - firefox-locale-de
    - gnome-session
    - gnome-terminal
  early-commands:
    - true
  late-commands:
    - |
      cat > /target/etc/xrdp/startwm.sh <<'SWM'
      #!/bin/sh
      export XDG_SESSION_TYPE=x11
      export XDG_CURRENT_DESKTOP=Ubuntu:GNOME
      export GNOME_SHELL_SESSION_MODE=ubuntu
      unset DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR
      exec dbus-launch --exit-with-session gnome-session --session=ubuntu
      SWM
      chmod 755 /target/etc/xrdp/startwm.sh
    - chroot /target adduser ${VM_USER} sudo
    - chroot /target adduser xrdp ssl-cert
    - chroot /target systemctl enable qemu-agent.service
    - chroot /target systemctl enable xrdp
    - |
      printf '[Unit]\nDescription=lab finalize\nAfter=network-online.target\n[Service]\nType=oneshot\nExecStart=/bin/bash -lc "apt-get -y update && DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade && apt-get -y autoremove && touch /var/lib/lab-postdone"\n[Install]\nWantedBy=multi-user.target\n' > /target/etc/systemd/system/lab-post.service
    - chroot /target systemctl enable lab-post.service
EOF

rm -f "$LAB_SEED/ubuntu-seed.iso"
xorriso -as mkisofs -o "$LAB_SEED/ubuntu-seed.iso" -volid autoinstall -r "$TMP/user-data" >/dev/null
ls -l "$LAB_SEED/ubuntu-seed.iso"; echo "ubuntu-seed.iso OK"

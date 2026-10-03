#!/bin/bash
# cachyos-live.sh - laeuft im CachyOS-Live-System, installiert headless per pacstrap.
set -eux
exec 2>&1 | tee /dev/kmsg

PW=$(cat /mnt/cdrom/vm.pass)
PUB=$(cat /mnt/cdrom/authorized_keys.pub)

# --- Netzwerk (networkd, ohne UI) ---
cat > /etc/systemd/network/20-wired.network <<'NET'
[Match]
Name=en* eth*
[Network]
DHCP=ipv4
NET
systemctl enable systemd-networkd systemd-resolved
systemctl start systemd-networkd systemd-resolved || true
for i in $(seq 30); do ping -c1 -W2 192.168.122.1 >/dev/null 2>&1 && break; sleep 2; done
ping -c1 -W2 arch-mirror.freedombone.net >/dev/null 2>&1 || true

DEV=/dev/vda
sgdisk --zap-all $DEV
sgdisk -n1:0:+2G -t1:ef00 -c1:ESP -n2:0:0 -t2:8300 -c2:LINUX $DEV
mkfs.fat -F32 -n ESP ${DEV}1
mkfs.btrfs -f -L lab ${DEV}2
mount -o compress=zstd ${DEV}2 /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount /mnt
mount -o compress=zstd,subvol=/@ ${DEV}2 /mnt
mkdir -p /mnt/home /mnt/boot /mnt/boot/efi
mount -o compress=zstd,subvol=/@home ${DEV}2 /mnt/home
mount ${DEV}1 /mnt/boot/efi

UUID2=$(blkid -s UUID -o value ${DEV}2); UUID1=$(blkid -s UUID -o value ${DEV}1)
cat > /mnt/etc/fstab <<FSTAB
UUID=$UUID2 / btrfs subvol=/@,compress=zstd,noatime 0 0
UUID=$UUID2 /home btrfs subvol=/@home,compress=zstd,noatime 0 0
UUID=$UUID1 /boot/efi vfat defaults,noatime 0 2
FSTAB

# --- Grundsystem + KDE + Tools ---
S="pacstrap -K /mnt base linux-cachyos linux-firmware grub sudo vim git wget \
openssh networkmanager qemu-guest-agent xrdp xorgxrdp xorg-server \
plasma-desktop konsole sddm --noconfirm"
$S || $S

# --- Chroot-Konfiguration ---
mnt_enter() { mount --rbind /dev /mnt/dev; mount -t proc proc /mnt/proc; chroot /mnt bash -c "$1"; }
echo vm-cachyos > /mnt/etc/hostname
echo 'KEYMAP=de-latin1' > /mnt/etc/vconsole.conf
echo 'LANG=de_DE.UTF-8' > /mnt/etc/locale.conf
sed -i 's/#de_DE.UTF-8 UTF-8/de_DE.UTF-8 UTF-8/' /mnt/etc/locale.gen
mnt_enter 'locale-gen >/dev/null 2>&1'
mnt_enter 'useradd -m -G wheel -s /bin/bash vmadmin'
echo "vmadmin:$PW" | mnt_enter 'chpasswd'
mnt_enter 'echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers.d/wheel'
mkdir -p /mnt/home/vmadmin/.ssh
echo "$PUB" > /mnt/home/vmadmin/.ssh/authorized_keys
chown -R 1000:1000 /mnt/home/vmadmin/.ssh; chmod 700 /mnt/home/vmadmin/.ssh; chmod 600 /mnt/home/vmadmin/.ssh/authorized_keys

cat > /mnt/etc/NetworkManager/system-connections/lab.nmconnection <<'NMC'
[connection]
id=lab
type=ethernet
autoconnect=true
[ipv4]
method=auto
NMC
chmod 600 /mnt/etc/NetworkManager/system-connections/lab.nmconnection

cat > /mnt/etc/xrdp/startwm.sh <<'SWM'
#!/bin/sh
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=KDE
unset DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR
exec dbus-launch --exit-with-session startplasma-x11
SWM
chmod 755 /mnt/etc/xrdp/startwm.sh

cat > /mnt/etc/systemd/system/lab-post.service <<'POST'
[Unit]
Description=lab final updates
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/bin/bash -c "sleep 10; pacman -Syu --noconfirm --needed; rm -f /var/cache/pacman/pkg/*; touch /var/lib/lab-postdone"
[Install]
WantedBy=multi-user.target
POST

mnt_enter 'mkinitcpio -P'
mnt_enter 'pacman -S --noconfirm --needed grub'
mnt_enter 'grub-install --target=i386-pc /dev/vda'
mnt_enter 'grub-mkconfig -o /boot/grub/grub.cfg'
echo 'GRUB_TIMEOUT=2' >> /mnt/etc/default/grub
mnt_enter 'grub-mkconfig -o /boot/grub/grub.cfg' || true
# pacman-Mirror -> Cachy
mnt_enter 'systemctl enable sshd NetworkManager qemu-guest-agent xrdp sddm lab-post.service'
echo "LAB_INSTALL_DONE"

sync; umount -R /mnt; poweroff

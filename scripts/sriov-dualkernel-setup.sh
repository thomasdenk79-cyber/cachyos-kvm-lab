#!/usr/bin/env bash
# SR-IOV Doppelkernel-Setup – P16 Gen2, 2026-10-13
# Ziel: Intel-i915-Backport (SR-IOV-PF) NUR auf Kernel 6.8.0-146, 7.0 bleibt unberuehrt.
# Grund: Intel-DKMS-postinst baut nur gegen den NEUESTEN Kernel (=7.0 -> Fehler).
# Trick: postinst-Build per Divert stubben, dann dkms-Zielbuild von Hand.
# Ausfuehren NACH dem anstehenden Reboot (normales 7.0-Booting).
# ROLLBACK: sudo apt purge intel-i915-dkms  (und ggf. apt autoremove --purge linux-image-6.8.0-146-generic linux-headers-6.8.0-146-generic)
set -euo pipefail
K="6.8.0-146-generic"
PKGDIR="$HOME/packages/sriov68"
DKMS_NAME="intel-i915-dkms"
DKMS_VER="1.25.2.16.250224.22-26"   # laut dkms.conf PACKAGE_VERSION

[ "$(id -u)" = 0 ] || { echo "sudo aufrufen!"; exit 1; }
dpkg -l linux-image-$K 2>/dev/null | grep -q '^ii' || { echo "Kernel $K fehlt – apt install ./linux-image-$K aus $PKGDIR"; exit 1; }

cleanup() { dpkg-divert --remove --rename /usr/lib/dkms/common.postinst >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "== 1) Divert-Stub gegen common.postinst (nur fuer diese Installation) =="
if ! dpkg-divert --list | grep -q 'diversion of /usr/lib/dkms/common.postinst'; then
  dpkg-divert --add --rename --divert /usr/lib/dkms/common.postinst.real /usr/lib/dkms/common.postinst
fi
printf '#!/bin/sh\nexit 0\n' > /usr/lib/dkms/common.postinst
chmod 755 /usr/lib/dkms/common.postinst

echo "== 2) Paket installieren (ohne 7.0-Build) =="
apt-get install -y "$PKGDIR"/intel-i915-dkms_*.deb   # postinst laeuft gegen Stub -> OK

echo "== 3) DKMS-Zielbuild fuer $K =="
dkms add -m $DKMS_NAME -v $DKMS_VER 2>/dev/null || true
if ! dkms install -m $DKMS_NAME -v $DKMS_VER -k $K; then
  echo "BUILD FEHLGESCHLAGEN – automatischer Rueckbau"
  apt-get purge -y $DKMS_NAME || true
  exit 1
fi

echo "== 4) Initramfs NUR fuer $K neu bauen =="
update-initramfs -u -k $K

echo "== 5) Modul-Optionen (Global, aber auf 7.0/In-tree harmlos: GuC+HuC=Standardpfad RPL) =="
cat > /etc/modprobe.d/i915-sriov.conf <<'EOF'
# SR-IOV PF-Vorbereitung (wirkt nur bei Kernel 6.8 + Backport i915)
options i915 enable_guc=3
EOF

echo "== 6) Selbsttest der 7.0-Unberuehrtheit =="
if test -e "/lib/modules/7.0.0-38-generic/updates/dkms/i915.ko" -o -e "/lib/modules/7.0.0-38-generic/updates/dkms/i915.ko.zst"; then
  echo "FATAL: Backport-Modul taucht im 7.0-Baum auf! -> purge"; apt-get purge -y $DKMS_NAME; exit 1
fi
depmod -n $K | awk '/^i915 /{print "i915 loest auf", $2, "auf fuer", K}' K=$K
lsinitramfs "/boot/initrd.img-$K" | grep -m1 -E 'i915' && echo "OK: initramfs $K haelt das Backport-Modul"
echo "FERTIG. Naechster Schritt: reboot, im GRUB-Menue '6.8.0-146' waehlen, dann sriov-verify.sh"

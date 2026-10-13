#!/usr/bin/env bash
# SR-IOV-Verifikation – auf dem 6.8.0-146-Boot ausfuehren (GRUB-Auswahl).
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "sudo!"; exit 1; }
PF=0000:00:02.0
echo "Kernel: $(uname -r)  (sollte 6.8.0-146-generic sein)"
echo "-- aktives i915-Modul (sollte .../updates/dkms/ zeigen):"
modinfo i915 | grep -E 'filename|^version'
echo "-- GuC-Status:"; cat /sys/module/i915/parameters/enable_guc 2>/dev/null
echo "-- sriov-Totalvfs:"; cat /sys/bus/pci/devices/$PF/sriov_totalvfs
echo "-- VFs anlegen (2):"
echo 2 > /sys/bus/pci/devices/$PF/sriov_numvfs && sleep 2
lspci -nn | grep -E '00:02\.[1-7]' || echo "KEINE VFS SICHTBAR – Backport-SR-IOV inaktiv"
echo "-- naechster Schritt (VF an Gaest VM haengen):"
cat <<'EOH'
 # VF nach vfio umbinden (ohne Host-Grafik-Verlust – der PF bleibt am i915!):
 echo vfio-pci > /sys/bus/pci/devices/0000:00:02.1/driver_override
 echo 0000:00:02.1 > /sys/bus/pci/drivers/vfio-pci/bind
 # libvirt: hostdev-XML auf type='pci' address 0000:00:02.1 (Guest: Intel Arc-Software installieren)
 # Hinweis: i915-vfio-pci (compat) liegt im Backport-Baum, bei Bedarf modprobe i915-vfio-pci
 # Windows-Gast-Gaste: Treiber = Intel Graphics driver fuer SR-IOV VF (Intel-Arc-Setup erkennt a788)
EOH
# Rueckbau VF: echo 0 > /sys/bus/pci/devices/$PF/sriov_numvfs

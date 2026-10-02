Research this as a Windows/KVM/Intune incident. Prioritize Microsoft Learn,
Microsoft Support, QEMU/libvirt/edk2 documentation, and official Intune docs.

The VM is Windows 11 25H2 on CachyOS (kernel 7.2.8-1-cachyos), QEMU 11.1.1,
libvirt 12.7.0, OVMF UEFI Secure Boot, swtpm TPM 2.0, 16 GiB RAM, 200 GiB
ZFS ZVOL, SATA disk during setup, e1000e NIC, stable UUID/SMBIOS/Disk serial/MAC.
The support ISO includes Autounattend.xml, NetKVM, vioscsi and qemu-ga.

Failure is reproducible after Windows OOBE reaches a reboot: Automatic Repair.
Windows Panther logs show:
- Found 1 updates in collection
- ZDP_Downloading
- ZDP_Installing
- Detected Reboot Required after ZDP install
- BFSVC BfspCopyFile(...\\EFI\\Microsoft\\Boot\\bootmgfw.efi) failed, Last Error=0x3
- BCD Failed to add system store, status c000000f

The EFI partition was not full: old 100 MiB ESP had 34 MiB used (36%); new
260 MiB ESP had about 35 MiB used (14%). SrtTrail tests for disk metadata,
volume contents, startup manager and filesystem all succeeded. ZFS pool is
healthy and current QEMU logs show no I/O failure.

Determine separately whether this is:
1. Windows OOBE ZDP servicing and reboot timing,
2. Intune/Autopilot Enrollment Status Page or policy reboot,
3. KVM/OVMF/TPM/SATA/virtio bootloader incompatibility,
4. a real BCD/EFI or ZFS corruption problem.

Check whether DynamicUpdate settings affect OOBE ZDP, whether Intune policies
such as VBS/security baseline/device lock/AppLocker/ESP can cause reboot loops,
and whether Windows 11 Intune/Autopilot has VM support limitations. Explain the
meaning of BFSVC error 0x3 and BCD c000000f when the EFI files later exist.
Recommend a supported, testable installation sequence and exact libvirt/QEMU
settings. Cite direct primary sources and identify any uncertainty.

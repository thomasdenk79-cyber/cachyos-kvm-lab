# Win11 automatic repair analysis package

Date: 2026-09-28
VM: `win11-siemens`

## Current finding

Windows reaches Automatic Repair after OOBE servicing. Secure Boot was tested
both enabled and disabled with the same result. The install media was removed
and the ZVOL was set as boot device 1 with the same result. ZFS, QEMU and
virtual block-device checks show no storage errors.

Offline Panther/Srt logs identify a Windows servicing/boot handoff failure:

- Windows installs KB5128942 / CloudExperienceHost components and requests a reboot.
- `BfspCopyFile(...bootmgfw_EX.efi...)` fails with error `0x3`.
- BCD system store update fails with `c000000f`.
- Srt disk, volume and target OS tests complete successfully.

## WinRE repair attempt

The user manually ran `chkdsk`, `DISM /revertpendingactions`, and `bcdboot`
with EFI `S:` and Windows `C:`. All commands reportedly completed without
errors, but reboot returned to Automatic Repair. Full details are in
`windows/winre-repair-attempt-20260928.txt`.

Snapshot protecting the pre-test state:

`zpcachyos/vms/win11@pre-secureboot-off-test-20260928`

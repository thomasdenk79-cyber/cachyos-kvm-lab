# Windows 11 KVM / Intune

The active VM path is `scripts/win11-vm.sh`. Historical Win11 material under
`archive/` is reference only. The VM keeps its registered UUID, MAC, SMBIOS
serial and disk serial. The system disk remains SATA/e1000e until stability is
proven.

## Recovery flow

1. Boot WinRE and open Command Prompt.
2. Insert the `WIN11_FIX` CD and run `X:\recover-good.cmd` for the known working fix.
3. Use `diag.cmd` to collect read-only state and the isolation scripts only
   from a matching snapshot.

`./scripts/win11-vm.sh fixiso` builds and attaches the ISO. Credentials are
read only from `~/win11_cred.txt`; no ISO or credential is committed.

The first confirmed Windows-Hello recovery baseline is `hello-working-fixed`.
The matching host-side QCOW2 backup is kept outside the repository.

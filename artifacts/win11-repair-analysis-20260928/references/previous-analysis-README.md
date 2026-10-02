# Windows 11 KVM / OOBE / Intune Browser-Agent Analysis Bundle

This bundle contains the active VM creation script, the generated support media
files, host-side QEMU/libvirt/ZFS evidence, and sanitized excerpts from the
failed Windows installation.

No credentials are included. In particular, `win11_cred.txt`, Microsoft
passwords, tokens, private keys, and external secret files were excluded.

## Environment

- CachyOS, kernel 7.2.8-1-cachyos
- QEMU 11.1.1, libvirt 12.7.0, OVMF UEFI, swtpm TPM 2.0
- Windows 11 25H2 German multi-edition ISO
- 200 GiB ZFS ZVOL `zpcachyos/vms/win11`
- 16 GiB RAM, 1 socket / 8 cores
- e1000e network adapter with stable VM identity

## Primary observed failure

During OOBE the logs show:

    Found 1 updates in collection
    ZDP_Downloading
    ZDP_Installing
    Detected Reboot Required after ZDP install

Immediately afterwards Windows Setup logs repeated failures copying
`bootmgfw.efi` to the EFI system partition and reports BCD status `c000000f`.
The EFI partition was not full: the previous 100 MiB ESP used 34 MiB (36%);
the fresh 260 MiB ESP used about 35 MiB (14%). SrtTrail reported all disk,
volume and boot-manager tests successful.

The active script now supports `--network-up`/`--network-down` and starts a
fresh install with the guest link down by default, because Microsoft documents
that OOBE ZDP updates are mandatory after network connection. The link can be
enabled after the base OOBE stage for Intune/MFA.

## Research questions

See `RESEARCH_PROMPT.md` for the complete browser-agent research request.

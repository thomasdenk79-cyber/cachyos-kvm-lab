# Root cause record

Date: 2026-09-29. The VM entered automatic repair after Intune provisioning.
Secure Boot keys, NVRAM, vTPM persistence, ESP size/FAT and VM identity were
verified and are not the cause. `SrtTrail.txt` reported a recently processed
boot binary and failed LCU removal (`0x825`). Offline testing showed that
`hypervisorlaunchtype=off` alone did not boot the VM. Disabling
`DeviceGuard\Scenarios\SystemGuard\Enabled`,
`RequireMicrosoftSignedBootChain` and VBS made it boot.

## Status

| Hypothesis | Status | Evidence |
|---|---|---|
| ESP full/FAT damaged | refuted | offline ESP: 512 MiB, healthy, low use |
| Missing Microsoft 2011/2023 keys | refuted | virt-fw-vars and verify |
| vTPM/NVRAM mismatch | refuted | persistent state and matching snapshot |
| System Guard/Secure Launch incompatible with KVM | confirmed as combined trigger | offline registry fix restored boot |
| Which DeviceGuard value alone is required | open | `test-systemguard.cmd` and `test-signedchain.cmd` |

On 2026-09-29 the combined recovery baseline booted through Windows Hello with
the desktop reachable. It was captured as the complete `hello-working-fixed`
snapshot (ZVOL, NVRAM and vTPM). A compressed QCOW2 copy was also verified.

## CPU / nested-virtualization matrix

The controlled 2x2 test reached the following result without changing the VM
identity or Secure-Boot/NVRAM/vTPM state:

| Nested virtualization | CPU passthrough | Result |
|---|---|---|
| off | off | boots |
| on | off | boots |
| off | on | boots |
| on | on | does not boot |

This confirms an interaction, not an individual failure: exposing the host CPU
passthrough features together with nested virtualization activates a CPU /
virtualization capability combination that conflicts with the Windows
Secure-Launch / DeviceGuard policy. The working reference remains
`hello-working-fixed`; the active safe configuration must keep at least one of
CPU passthrough or nested virtualization disabled.

The isolation tests must start from `hello-working-fixed`; do not rebuild or
change VM identity.

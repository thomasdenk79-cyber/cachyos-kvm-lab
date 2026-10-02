# Open items

- Request a Secure Launch/System Guard exception for DINAC4A0E44045F.
- Windows Hello recovery baseline is captured; do not alter it before testing.
- CPU passthrough alone was verified working.
- Host-model with nested virtualization exposed was also verified working.
- Combined passthrough+nested mode fails; keep nested virtualization disabled.
- Current requested baseline is CPU passthrough ON, nested virtualization OFF,
  32 GiB RAM, 12 vCPU and 2 MiB hugepages. Host sysctl requests 16,384 pages;
  runtime allocation reached only 5,947 pages after compaction. Do not start
  the VM until the host reports all 16,384 pages reserved after reboot.
  The active systemd-boot entry now reserves them early with
  `hugepagesz=2M hugepages=16384`.
- Run isolation tests A/B from `hello-working-fixed`.
- Test `vbs-on-test.cmd` only after a fresh checkpoint.
- Restore diagnostic BCD flags with `diag-restore.cmd` when finished.
- Keep virtio-scsi/virtio-net deferred until stable operation.

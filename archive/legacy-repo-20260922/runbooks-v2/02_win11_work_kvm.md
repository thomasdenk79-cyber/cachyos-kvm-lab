# Windows 11 Work VM

## Lokale Konfiguration

```yaml
# In diesem Dokument integrierte Vorlage; Werte lokal halten, nicht öffentlich committen.
windows_vm:
  name: windows11-generic-test
  state: existing
  identity_mode: preserve
  identity:
    uuid: e39af3f0-0d5f-4932-8934-9fe33d19ce86
    smbios_serial: WIN11-E39AF3F00D5F493289349FE33D19CE86
    disk_serial: WIN11-E39AF3F00D5F493289349FE33D19CE86-DISK
    mac: 52:54:00:df:a5:d1
    preserve:
      - uuid
      - smbios_serial
      - disk_serial
      - mac
      - ovmf_nvram
      - vtpm_state

  firmware:
    machine: q35
    uefi: true
    secure_boot: true
    tpm:
      version: "2.0"
      model: tpm-crb

  storage:
    path: /mnt/data/vm-images/win11.raw
    format: raw
    bus_initial: sata
    bus_tuned: virtio
    cache: none
    io: io_uring
    discard: unmap
    detect_zeroes: unmap
    queues: 4
    iothreads: 1

  network:
    mode: libvirt-nat
    network: default
    model_initial: e1000e
    model_tuned: virtio
    queues: 4

  graphics:
    baseline: virtio-dod
    access: rdp
    shared_igpu: auto
    fallback: virtio-dod
```

## CPU-Policy

```yaml
cpu_policy:
  model:
    mode: host-passthrough
    check: none
    migratable: false
    cache: passthrough
    require_features: [invtsc]

  topology:
    sockets: 1
    dies: 1
    default_guest_threads_per_core: 1
    formula: sockets * dies * cores * threads == vcpus

  sizing:
    minimum_vcpus: 2
    even_vcpu_count: true
    preserve_host_logical_cpus: 2
    rules:
      - host_logical_cpus_min: 24
        vm_percent: 60
      - host_logical_cpus_min: 16
        vm_percent: 65
      - host_logical_cpus_min: 12
        vm_percent: 66
      - host_logical_cpus_min: 1
        vm_percent: 50

  hybrid:
    prefer_p_cores: true
    use_e_cores_for_vm: false
    mix_core_types: false

  smt:
    default: flatten
    guest_threads_per_core: 1
    native_mode_requires:
      - host_smt_active
      - full_sibling_pairs
      - homogeneous_core_type
      - exact_1_to_1_pinning

  pinning:
    enabled_after_baseline: true
    one_vcpu_per_host_logical_cpu: true
    duplicate_host_cpu_assignment: false
    emulator_overlap_with_vcpu: false
    iothread_overlap_with_vcpu: false

  qemu_threads:
    emulator_host_cpus: 1
    iothreads: 1
    iothread_host_cpus: 1

  numa:
    detect: true
    prefer_single_node: true
    strict_only_when_cpu_and_memory_fit: true
```

## CPU-Beispiele

```yaml
examples:
  zbook_12_threads:
    calculated_vcpus: 8
    topology:
      sockets: 1
      dies: 1
      cores: 8
      threads: 1

  hybrid_16_selected_p_threads:
    calculated_vcpus: 16
    topology:
      sockets: 1
      dies: 1
      cores: 16
      threads: 1

  optional_native_smt_8_vcpu:
    requirements_met: true
    topology:
      sockets: 1
      dies: 1
      cores: 4
      threads: 2
```

## Discovery

```bash
lscpu --json
lscpu -e=CPU,NODE,SOCKET,DIE,CORE,ONLINE,MAXMHZ
numactl --hardware
for c in /sys/devices/system/cpu/cpu[0-9]*; do
  id=${c##*cpu}
  printf '%s socket=%s die=%s core=%s siblings=%s maxkhz=%s coretype=%s\n' \
    "$id" \
    "$(cat "$c/topology/physical_package_id")" \
    "$(cat "$c/topology/die_id" 2>/dev/null || echo 0)" \
    "$(cat "$c/topology/core_id")" \
    "$(cat "$c/topology/thread_siblings_list")" \
    "$(cat "$c/cpufreq/cpuinfo_max_freq" 2>/dev/null || echo 0)" \
    "$(cat "$c/topology/core_type" 2>/dev/null || echo unknown)"
done
```

## Baseline vor Tuning

```yaml
baseline:
  disk_bus: sata
  nic_model: e1000e
  graphics: qxl_or_virtio_dod
  cpu_pinning: false
  shared_gpu: false
  required_before_tuning:
    - windows_boots
    - windows_update_complete
    - rdp_enabled
    - identity_verified
    - full_backup_complete
```

## Identität prüfen

```bash
VM=windows11-generic-test
virsh domuuid "$VM"
virsh domiflist "$VM"
virsh dumpxml "$VM" | grep -E "<uuid>|<serial>|<mac |<nvram>|<tpm|<source file=.*win11"
```

```powershell
Get-CimInstance Win32_BIOS | Select-Object SerialNumber
Get-CimInstance Win32_ComputerSystemProduct | Select-Object UUID
Get-CimInstance Win32_DiskDrive | Select-Object Model,SerialNumber
Get-NetAdapter | Select-Object Name,MacAddress
```

## Backup-Gate

```bash
VM=windows11-generic-test
UUID=$(virsh domuuid "$VM")
OUT="$HOME/vm-backup/$VM-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
virsh shutdown "$VM"
while [[ $(virsh domstate "$VM") != 'shut off' ]]; do sleep 2; done
virsh dumpxml "$VM" > "$OUT/domain.xml"
sudo cp --reflink=auto /var/lib/libvirt/qemu/nvram/${VM}_VARS.fd "$OUT/"
sudo tar -C /var/lib/libvirt/swtpm -czf "$OUT/vtpm.tgz" "$UUID"
sudo cp --sparse=always /mnt/data/vm-images/win11.raw "$OUT/"
sha256sum "$OUT"/* > "$OUT/SHA256SUMS"
```

```yaml
gate:
  name: baseline_backup
  pass_if:
    - domain_xml_present
    - raw_image_present
    - ovmf_nvram_present
    - vtpm_state_present
    - checksums_present
```

## VirtIO-Treiber aktivieren

```bash
VM=windows11-generic-test
qemu-img create -f raw /mnt/data/vm-images/virtio-trigger.raw 1G
virsh attach-disk "$VM" /mnt/data/vm-images/virtio-trigger.raw vdb --targetbus virtio --persistent
virsh start "$VM"
```

```powershell
Start-Process msiexec.exe -ArgumentList '/i E:\virtio-win-gt-x64.msi /qn' -Wait
Start-Process msiexec.exe -ArgumentList '/i E:\guest-agent\qemu-ga-x86_64.msi /qn' -Wait
Get-WindowsDriver -Online | Where-Object ProviderName -like '*Red Hat*'
Get-Disk
```

```bash
virsh shutdown "$VM"
virsh detach-disk "$VM" vdb --persistent
rm /mnt/data/vm-images/virtio-trigger.raw
```

## Getunte Domain-XML-Fragmente

```xml
<vcpu placement='static'>8</vcpu>
<iothreads>1</iothreads>

<cpu mode='host-passthrough' check='none' migratable='off'>
  <topology sockets='1' dies='1' cores='8' threads='1'/>
  <cache mode='passthrough'/>
  <feature policy='require' name='invtsc'/>
</cpu>

<features>
  <acpi/>
  <apic/>
  <hyperv mode='custom'>
    <relaxed state='on'/>
    <vapic state='on'/>
    <spinlocks state='on' retries='8191'/>
    <vpindex state='on'/>
    <synic state='on'/>
    <stimer state='on'><direct state='on'/></stimer>
    <reset state='on'/>
    <frequencies state='on'/>
    <reenlightenment state='on'/>
    <tlbflush state='on'/>
    <ipi state='on'/>
  </hyperv>
  <vmport state='off'/>
  <smm state='on'/>
</features>

<clock offset='localtime'>
  <timer name='rtc' tickpolicy='catchup'/>
  <timer name='pit' tickpolicy='delay'/>
  <timer name='hpet' present='no'/>
  <timer name='hypervclock' present='yes'/>
</clock>

<memoryBacking>
  <source type='memfd'/>
  <access mode='shared'/>
</memoryBacking>
<memballoon model='none'/>
```

## Pinning-Vorlage

```yaml
pinning_plan:
  selected_vcpu_host_cpus: GENERATED
  reserved_host_cpus:
    emulator: GENERATED
    iothread_1: GENERATED
  constraints:
    - all_selected_cpus_online
    - unique_host_cpu_per_vcpu
    - p_cores_only_on_hybrid_cpu
    - same_numa_node_when_possible
    - no_emulator_or_iothread_overlap
```

```xml
<cputune>
  <vcpupin vcpu='0' cpuset='AUTO'/>
  <vcpupin vcpu='1' cpuset='AUTO'/>
  <vcpupin vcpu='2' cpuset='AUTO'/>
  <vcpupin vcpu='3' cpuset='AUTO'/>
  <vcpupin vcpu='4' cpuset='AUTO'/>
  <vcpupin vcpu='5' cpuset='AUTO'/>
  <vcpupin vcpu='6' cpuset='AUTO'/>
  <vcpupin vcpu='7' cpuset='AUTO'/>
  <emulatorpin cpuset='AUTO_HOST'/>
  <iothreadpin iothread='1' cpuset='AUTO_IO'/>
</cputune>
```

## Storage / Netzwerk

```xml
<disk type='file' device='disk'>
  <driver name='qemu' type='raw' cache='none' io='io_uring'
          discard='unmap' detect_zeroes='unmap' queues='4' iothread='1'/>
  <source file='/mnt/data/vm-images/win11.raw'/>
  <target dev='vda' bus='virtio'/>
  <serial>WIN11-E39AF3F00D5F493289349FE33D19CE86-DISK</serial>
</disk>

<interface type='network'>
  <mac address='52:54:00:df:a5:d1'/>
  <source network='default'/>
  <model type='virtio'/>
  <driver name='vhost' queues='4'/>
</interface>
```

## Shared-GPU-Fallback

```yaml
graphics_policy:
  baseline:
    device: virtio-vga
    driver: virtio-dod
    spice_streaming: off
    access: rdp
  experiment:
    select_by_capability:
      sr_iov: intel-sriov
      gvt_g: intel-gvtg
    keep_dgpu_on_host: true
    keep_egpu_on_host: true
  rollback:
    device: virtio-vga
    access: rdp
```

## Verify

```bash
VM=windows11-generic-test
virsh dumpxml "$VM" > /tmp/$VM.xml
virsh vcpupin "$VM"
virsh emulatorpin "$VM"
virsh iothreadinfo "$VM"
virsh numatune "$VM"
grep -E "host-passthrough|topology|hyperv|hpet|cache='none'|discard='unmap'|memballoon" /tmp/$VM.xml
```

```powershell
Get-CimInstance Win32_ComputerSystem | Select-Object NumberOfProcessors,NumberOfLogicalProcessors
Get-CimInstance Win32_Processor | Select-Object SocketDesignation,NumberOfCores,NumberOfLogicalProcessors
Get-PnpDevice | Where-Object Status -ne OK
```

```yaml
cpu_invariants:
  - vcpu_count_equals_sockets_times_dies_times_cores_times_threads
  - sockets_equals_1
  - dies_equals_1
  - no_duplicate_host_cpu_assignments
  - no_p_core_e_core_mixing
  - no_vcpu_emulator_overlap
  - no_vcpu_iothread_overlap
  - at_least_two_host_logical_cpus_reserved
```

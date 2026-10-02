# Intel-Iris-Xe-SR-IOV-Experiment

Stand: 2026-10-02

Der Rechner hat einen Intel Core i5-1145G7 (Tiger Lake) mit Iris Xe. Der
normale CachyOS-Kernel stellt derzeit keine `sriov_numvfs`-Funktion und keine
`mdev_supported_types` bereit. GVT-g ist für diese Generation nicht der
passende Mechanismus. Der Test verwendet deshalb den experimentellen
Out-of-tree-Treiber `strongtz/i915-sriov-dkms`, fest auf Release `2026.09.16`
und den Kernel-7.2-Zweig.

Intel führt Tiger Lake in der aktuellen Support-Tabelle als nicht unterstützte
Grafikvirtualisierungsfamilie. Der DKMS-Treiber ist ein Community-Projekt ohne
Intel-Support. Ein erfolgreicher Build beweist daher nicht, dass VFs stabil
mit Windows oder Linux-Gästen funktionieren.

## Vorbereitung

```bash
./scripts/intel-igpu-sriov-experiment.sh check
./scripts/intel-igpu-sriov-experiment.sh prepare
```

`prepare`:

- prüft CPU, Iris-Xe-PCI-Gerät, `linux-cachyos-headers`, DKMS und Secure Boot;
- sichert `/boot/loader/entries` unter `.vm-lab/intel-igpu-sriov/backup-*`;
- baut das gepinnte DKMS-Paket und regeneriert die initramfs;
- legt ausschließlich den zusätzlichen Eintrag
  `intel-sriov-experimental.conf` an.

Der Standard-Eintrag wird nicht geändert und es erfolgt kein automatischer
Neustart. Der Testeintrag enthält:

```text
intel_iommu=on iommu=pt i915.enable_guc=3 i915.max_vfs=3
i915.xelp_enable_ccs=1 module_blacklist=xe
```

## Testboot und VF-Prüfung

Im systemd-boot-Menü den Eintrag **CachyOS (Intel iGPU SR-IOV experiment)**
einmalig auswählen. Danach zunächst nur prüfen:

```bash
./scripts/intel-igpu-sriov-experiment.sh status
cat /sys/devices/pci0000:00/0000:00:02.0/sriov_totalvfs
cat /sys/devices/pci0000:00/0000:00:02.0/sriov_numvfs
```

Wenn `sriov_totalvfs` größer als null ist, können testweise VFs erzeugt
werden:

```bash
echo 1 | sudo tee /sys/devices/pci0000:00/0000:00:02.0/sriov_numvfs
lspci -Dnn | grep -E '00:02\.[1-9]'
```

Erst wenn dieser Test stabil ist, darf eine VF (`0000:00:02.1` usw.) an eine
VM gegeben werden. Die PF `0000:00:02.0` darf nicht an eine VM durchgereicht
werden. Für den ersten Lauf wird die automatische VF-Erzeugung absichtlich
nicht aktiviert.

Alternativ fordert das Skript die konfigurierte Anzahl (standardmäßig drei)
an:

```bash
./scripts/intel-igpu-sriov-experiment.sh create-vfs
```

Optional (standardmäßig drei VFs für die drei Lab-Gäste; für mehr oder weniger
explizit setzen):

```bash
./scripts/intel-igpu-sriov-experiment.sh enable-vfs
```

Das schreibt eine tmpfiles-Regel für drei VFs. `IGPU_SRIOV_VFS=1`, `=2` oder `=7`
kann die Anzahl vor dem Aufruf überschreiben. Wegen des experimentellen
Treiberpfads sollte dies erst nach einem erfolgreichen manuellen Test erfolgen.

## Recovery nach Grafik- oder Bootfehler

Im systemd-boot-Menü den normalen Eintrag `Linux CachyOS` starten. Wenn der
experimentelle Eintrag hängen bleibt, beim Bootmenü `e` drücken und ergänzen:

```text
module_blacklist=i915,xe
```

Danach wieder normal booten und das Experiment entfernen:

```bash
./scripts/intel-igpu-sriov-experiment.sh remove
```

Das Skript löscht den zusätzlichen Boot-Eintrag, entfernt die tmpfiles-Regel,
entfernt das DKMS-Paket und baut die initramfs erneut. Die gesicherten
Bootdateien bleiben zur manuellen Wiederherstellung erhalten.

## Bekannte Grenzen

- Secure Boot muss deaktiviert bleiben oder die DKMS-Module müssen selbst
  signiert werden.
- Der Host und ein Gast benötigen kompatible SR-IOV-Treiber; eine VF-Erzeugung
  allein garantiert keine funktionierende Windows-Grafik.
- Ein erfolgreicher Test kann den i915-Desktop destabilisieren. Deshalb bleibt
  der Standard-Bootpfad unverändert und `enable-vfs` ist getrennt.

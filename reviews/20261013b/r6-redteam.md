# Red‑Team‑Analyse: 7 potenzielle Angriffe auf das Virtualisierungslabor

**Ziel:** Aufzeigen von Schwachstellen, die die Umgebung bei der nächsten Session zerstören könnten. Jede Attacke enthält die zitierte Stelle, ein Szenario und eine Gegenmaßnahme (ein einziger Shell‑Befehl).

---

## 1. IOMMU‑Aktivierung vs. notwendiger Reboot
**Zitatstelle**
- TODO.md Zeile 22‑23: `**IOMMU aktiv?** intel_iommu=on iommu=pt ist bereits in /etc/default/grub`
- Labor‑Doku Zeile 73‑75: `intel_iommu=on iommu=pt ergänzt … **kein Reboot erzwungen** – greift beim nächsten regulären Neustart.`
**Szenario**
Ein Folge‑Agent, der nur TODO.md liest, geht davon aus, dass IOMMU bereits aktiv ist und startet sofort VMs. Da der Kernel‑Reboot noch nicht erfolgt ist, bleibt IOMMU inaktiv und neue VM‑Starts triggern erneut den KVM‑Kernel‑Bug.
**Gegenmaßnahme**
```bash
sudo update-grub && sudo reboot
```
---

## 2. Snapshot‑Löschung ohne `--metadata`
**Zitatstelle**
- TODO.md Zeile 116‑118: `Snapshot nur so aufraeumen … Loeschen nur mit --metadata: sudo virsh snapshot-delete kvm-siemens pre-tune-20261013 --metadata`
**Szenario**
Ein Agent verwendet `virsh snapshot-delete …` ohne das Flag `--metadata`. Das XML‑Backing‑Chain‑File bleibt referenziert und das Laufwerk wird unbrauchbar – zukünftige Snapshots brechen.
**Gegenmaßnahme**
```bash
sudo virsh snapshot-delete kvm-siemens pre-tune-20261013 --metadata
```
---

## 3. Zufälliger XAUTHORITY‑Dateiname & wechselnde DISPLAY‑Nummer
**Zitatstelle**
- TODO.md Zeile 103‑108: `XAUTHORITY‑Dateiname endet zufaellig (xauth_*), Display‑Nummer wechselte heute auf :4 … eval "$(systemctl --user show-environment | grep -E '^(DISPLAY|XAUTHORITY|WAYLAND_DISPLAY|XDG_RUNTIME_DIR)=')"`
**Szenario**
Wenn das System bei der nächsten Session eine andere DISPLAY‑Nummer (`:0` oder `:1`) verwendet, schlägt die `eval`‑Anweisung fehl, `virt‑viewer` startet ohne gültige Anzeige und die VM‑Konsolenzugriffe kippen.
**Gegenmaßnahme**
```bash
eval "$(systemctl --user show-environment | grep -E '^(DISPLAY|XAUTHORITY|WAYLAND_DISPLAY|XDG_RUNTIME_DIR)=')" || export DISPLAY=:0
```
---

## 4. Fehlendes Re‑Login nach `usermod -aG libvirt`
**Zitatstelle**
- TODO.md Zeile 122‑123: `sudo usermod -aG libvirt z000g9hu + Re-Login (virsh‑Kommandos brauchen sonst immer sudo -n)`
**Szenario**
Ein Bot fügt den Nutzer zur Gruppe hinzu, führt aber **keinen** Re‑Login durch. Alle nachfolgenden `virsh`‑Aufrufe benötigen `sudo`, was in automatisierten Skripten zu Permission‑Fehlern führt.
**Gegenmaßnahme**
```bash
newgrp libvirt
```
---

## 5. Annahme: VMware & VirtualBox bleiben von KVM‑Bug unbeeinflusst
**Zitatstelle**
- Labor‑Doku Zeile 67: `VMware/VBox sind NICHT betroffen (andere Treiber).`
- TODO.md Zeile 16‑17: `User testet parallel VMware … + VirtualBox … – Reboot nur nach Benutzerfreigabe. Beide sind nicht betroffen.`
**Szenario**
Ein nachfolgender Agent überspringt die Status‑Checks für diese Hypervisoren. Nach einem Kernel‑Update können jedoch auch die VMware‑ und VirtualBox‑Treiber den gleichen VMX‑State‑Corruption‑Pfad benutzen, wodurch beide Umgebungen pausieren.
**Gegenmaßnahme**
```bash
systemctl is-active vmware && VBoxManage list runningvms
```
---

## 6. Unrealistische VRAM‑Erwartungen (8 GB/16 GB) vs. QXL‑Limit
**Zitatstelle**
- Labor‑Doku Zeile 27‑30: `VRAM‑Wahrheit: … QXL‑Max = 256 MB + 16 MB vgamem; 16 GB „VRAM“ ist in keinem virtuellen Adapter realistisch.`
- TODO.md Zeile 48: `Vergleich framerate/latency vs. QXL‑auto_glz …` (implizit werden größere Werte erwartet).
**Szenario**
Ein Skript generiert XML‑Einträge mit `vram='16384'` (16 GB). libvirt verwirft die VM‑Definition, sodass das Labor nicht startfähig ist.
**Gegenmaßnahme**
```bash
sudo sed -i 's/vram="[0-9]*"/vram="262144"/' /etc/libvirt/qemu/kvm-siemens.xml
```
---

## 7. Verlassen auf den Reboot zur Behebung des KVM‑Kernel‑Bugs
**Zitatstelle**
- TODO.md Zeile 7‑15: `SofortBLOCKER: Host‑KVM defekt → Reboot nötig … Fix: sauberer Reboot.`
- Labor‑Doku Zeile 60‑69: `KVM‑Kernelfehler … Fix: Reboot (bringt zugleich IOMMU).`
**Szenario**
Wird der Reboot aus irgendeinem Grund (z. B. hängender Service) nicht erfolgreich durchgeführt, bleibt der VMX‑State‑Corruption‑Zustand bestehen. Der Agent springt weiter zu den VM‑Starts und verursacht sofortige Pausierungen.
**Gegenmaßnahme**
```bash
if dmesg | grep -q 'kvm_intel: vmwrite failed'; then echo "KVM‑Bug noch aktiv – Abort"; else echo "KVM‑Bug behoben"; fi
```
---

*Hinweis:* Jeder Befehl kann als einzelne Zeile in ein Automatisierungsskript integriert werden, um das Labor vor den aufgezeigten Fehlermustern zu schützen.

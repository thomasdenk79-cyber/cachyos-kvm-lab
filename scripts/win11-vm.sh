#!/usr/bin/env bash
# =============================================================================
# win11-vm.sh  -  Windows 11 Pro (Siemens Intune/Autopilot) als KVM-VM auf ZFS
#
# EIN Skript. Ersetzt: win11-zvol-vm.sh, win11-first-vm.sh, *.profile
#
# Grundsaetze
#   - Domain-XML und autounattend.xml stehen unten als lesbare Vorlagen.
#     Kein virt-install, keine nachtraegliche Python-/sed-Reparatur.
#   - verify ist eine harte Sperre: ein FAIL -> kein Start.
#   - Identitaet (UUID/MAC/SMBIOS/Disk-Serial) ist an Autopilot registriert.
#
# Ablauf (Details: ./win11-vm.sh help)
#   ./win11-vm.sh rebuild --force     Host vorbereiten, alles neu, Setup startet
#   ./win11-vm.sh link up             nach erstem Desktop-Login (lokales Konto)
#   ./win11-vm.sh media eject         Windows-ISO + Unattend-ISO entfernen
#   ./win11-vm.sh snapshot <name>     ZVOL + NVRAM + vTPM (VM muss aus sein)
#   ./win11-vm.sh rollback <name>
# =============================================================================
set -Eeuo pipefail

# ============================ KONFIGURATION ===================================
# --- Identitaet: an Autopilot registriert, NICHT aendern ---
VM=win11-siemens
UUID=e39af3f0-0d5f-4932-8934-9fe33d19ce86
MAC=52:54:00:6b:1e:33
# Client DINAC4A0E44045F, registered 2026-09-29; old identity cancelled.
SMBIOS_MANUFACTURER=QEMU
SMBIOS_PRODUCT="KVM Windows 11"
SMBIOS_SERIAL=WIN11-1D7E355EEE554A218ACE9C4A0E44045F
DISK_SERIAL=WIN11-1D7E355EEE554A218ACE9C4A0E4404 # QEMU-Limit: 36 Zeichen

# --- Hardware ---
RAM_MIB=32768
VCPUS=12
MACHINE=pc-q35-11.1

# --- ZFS ---
POOL=zpcachyos
ZVOL=$POOL/vms/win11
VOLSIZE=200G
VOLBLOCK=64K            # nach create unveraenderlich

# --- Firmware / TPM ---
OVMF_CODE=/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd
OVMF_VARS_EMPTY=/usr/share/edk2/x64/OVMF_VARS.4m.fd
OVMF_VARS_TPL=/var/lib/libvirt/boot/OVMF_VARS.4m.ms-enrolled.fd
NVRAM=/var/lib/libvirt/qemu/nvram/${VM}_VARS.fd
SWTPM_DIR=/var/lib/libvirt/swtpm/$UUID
SNAP_DIR=/var/lib/libvirt/snapshots/$VM

# --- Medien ---
BOOT=/var/lib/libvirt/boot
WIN_ISO=${WIN11_ISO:-$BOOT/Windows11-25H2-Official-Multi-DE.iso}
VIRTIO_ISO=$BOOT/virtio-win.iso
FIX_ISO=$BOOT/win11-fix.iso
FIX_DIR=${WIN11_FIX_DIR:-$PWD/winre}
VIRTIO_URL=https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso
UNATTEND_ISO=$BOOT/$VM-autounattend.iso
CRED_FILE=${WIN11_CREDENTIAL_FILE:-$HOME/win11_cred.txt}   # vm_user=... / vm_password=...

# --- Windows-Setup ---
WIN_EDITION="Windows 11 Pro"                  # /IMAGE/NAME in install.wim
WIN_GENERIC_KEY=VK7JG-NPHTM-C97JM-9MPGT-3V66T # Microsoft-Installationskey Pro (aktiviert nicht)
LOCALE=de-DE
INPUT_LOCALE=0407:00000407
TIMEZONE="W. Europe Standard Time"

# --- Laufzeit-Schalter ---
LINK=${WIN11_LINK:-down}
BOOT_FROM_ISO=0
ATTACH_INSTALL_MEDIA=0
ATTACH_VIRTIO_MEDIA=${WIN11_ATTACH_VIRTIO:-0}

# --- Host-Pakete (CachyOS/Arch) ---
PKGS=(qemu-desktop libvirt virt-viewer virt-manager edk2-ovmf virt-firmware
      swtpm dnsmasq libxml2 libisoburn curl)
SYSCTL_FILE=/etc/sysctl.d/80-win11-hugepages.conf
SYSCTL_SOURCE=${WIN11_SYSCTL_SOURCE:-$PWD/config/sysctl.d/80-win11-hugepages.conf}

# ============================ HELFER ==========================================
log()  { printf '\033[1;34m[win11]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn ]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[fail ]\033[0m %s\n' "$*" >&2; exit 1; }
R()    { if ((EUID==0)); then "$@"; else sudo "$@"; fi; }
v()    { R virsh -c qemu:///system "$@"; }
state(){ v domstate "$VM" 2>/dev/null | head -1 || echo absent; }
need_off(){ [[ $(state) == "shut off" ]] || die "VM muss 'shut off' sein (ist: $(state))."; }
xesc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }

# ============================ HOST-VORBEREITUNG ===============================
# Idempotent: installiert/aktiviert nur, was fehlt.
host_setup() {
  command -v pacman >/dev/null || die "Nur fuer CachyOS/Arch."
  local miss=() p
  for p in "${PKGS[@]}"; do pacman -Q "$p" &>/dev/null || miss+=("$p"); done
  ((${#miss[@]})) && { log "Installiere: ${miss[*]}"; R pacman -S --needed --noconfirm "${miss[@]}"; }
  command -v zfs >/dev/null || die "zfs-utils fehlen (CachyOS: zfs-utils + Kernelmodul)."
  zfs list -H -o name "$POOL" &>/dev/null || die "ZFS-Pool fehlt: $POOL"

  R systemctl enable --now libvirtd.service >/dev/null 2>&1 \
    || R systemctl enable --now virtqemud.socket virtnetworkd.socket >/dev/null
  id -nG "${SUDO_USER:-$USER}" | grep -qw libvirt || R usermod -aG libvirt,kvm "${SUDO_USER:-$USER}"

  if ! v net-info default &>/dev/null; then
    v net-define /usr/share/libvirt/networks/default.xml >/dev/null
  fi
  [[ $(v net-info default | awk -F': *' '/^Active/{print $2}') == yes ]] || v net-start default >/dev/null
  v net-autostart default >/dev/null

  R install -d -m 0755 "$BOOT"
  [[ -f $SYSCTL_SOURCE ]] || die "Hugepage-Konfiguration fehlt: $SYSCTL_SOURCE"
  # Genau eine aktive Win11-Sysctl-Datei verwalten. Ältere/conflicting Dateien
  # werden nur deaktiviert, damit ihre Werte nicht später wieder überschreiben.
  while IFS= read -r f; do
    [[ $f == "$SYSCTL_FILE" ]] && continue
    R mv "$f" "$f.disabled"
    log "Deaktiviere widersprechende Sysctl-Datei: $f"
  done < <(R find /etc/sysctl.d -maxdepth 1 -type f -iname '*win11*.conf' -print 2>/dev/null)
  R install -m 0644 "$SYSCTL_SOURCE" "$SYSCTL_FILE"
  R sysctl -p "$SYSCTL_FILE" >/dev/null
  local hp
  hp=$(< /proc/sys/vm/nr_hugepages)
  (( hp >= 16384 )) || die "Nur $hp von 16384 Hugepages reserviert; Host-Neustart erforderlich."
  [[ -f $VIRTIO_ISO ]] || { log "Lade virtio-win.iso"; R curl -fL --retry 3 -o "$VIRTIO_ISO" "$VIRTIO_URL"; }
  [[ -f $WIN_ISO ]] || die "Windows-ISO fehlt: $WIN_ISO  (WIN11_ISO=/pfad/zur.iso setzen)"
  [[ -f $OVMF_CODE && -f $OVMF_VARS_EMPTY ]] || die "OVMF fehlt (edk2-ovmf)."

  # Secure-Boot-Vorlage mit Microsoft KEK/DB 2011 + 2023
  if ! R virt-fw-vars -i "$OVMF_VARS_TPL" --print 2>/dev/null | grep -q '^name=PK '; then
    log "Erzeuge NVRAM-Vorlage mit Microsoft-Keys: $OVMF_VARS_TPL"
    R virt-fw-vars -i "$OVMF_VARS_EMPTY" -o "$OVMF_VARS_TPL" \
      --enroll-microsoft --microsoft-kek all --microsoft-db all --sb
    R chmod 0644 "$OVMF_VARS_TPL"
  fi
  log "Host bereit."
}

# ============================ VORLAGE: autounattend.xml =======================
# Automatisiert: Sprache, Partitionierung (ESP 512 MiB), Edition Pro,
# lokales Konto (Netz ist aus -> kein Autopilot), keine Updates in der OOBE.
# Die Datei wird nach dem ersten Login aus Panther geloescht.
emit_unattend() {
  local user=$1 pass=$2 account=""
  if [[ -n $user ]]; then
    account="
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action=\"add\">
            <Name>$(xesc "$user")</Name>
            <DisplayName>$(xesc "$user")</DisplayName>
            <Group>Administrators</Group>
            <Password><Value>$(xesc "$pass")</Value><PlainText>true</PlainText></Password>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>"
  fi
  cat <<XML
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend"
          xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">

  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <SetupUILanguage><UILanguage>$LOCALE</UILanguage></SetupUILanguage>
      <InputLocale>$INPUT_LOCALE</InputLocale>
      <SystemLocale>$LOCALE</SystemLocale>
      <UILanguage>$LOCALE</UILanguage>
      <UserLocale>$LOCALE</UserLocale>
    </component>
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <DiskConfiguration>
        <Disk wcm:action="add">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <CreatePartition wcm:action="add"><Order>1</Order><Type>EFI</Type><Size>512</Size></CreatePartition>
            <CreatePartition wcm:action="add"><Order>2</Order><Type>MSR</Type><Size>16</Size></CreatePartition>
            <CreatePartition wcm:action="add"><Order>3</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Format>FAT32</Format><Label>System</Label></ModifyPartition>
            <ModifyPartition wcm:action="add"><Order>2</Order><PartitionID>3</PartitionID><Format>NTFS</Format><Label>Windows</Label><Letter>C</Letter></ModifyPartition>
          </ModifyPartitions>
        </Disk>
      </DiskConfiguration>
      <ImageInstall>
        <OSImage>
          <InstallFrom>
            <MetaData wcm:action="add"><Key>/IMAGE/NAME</Key><Value>$WIN_EDITION</Value></MetaData>
          </InstallFrom>
          <InstallTo><DiskID>0</DiskID><PartitionID>3</PartitionID></InstallTo>
          <WillShowUI>OnError</WillShowUI>
        </OSImage>
      </ImageInstall>
      <UserData>
        <AcceptEula>true</AcceptEula>
        <ProductKey><Key>$WIN_GENERIC_KEY</Key><WillShowUI>OnError</WillShowUI></ProductKey>
      </UserData>
    </component>
  </settings>

  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <InputLocale>$INPUT_LOCALE</InputLocale>
      <SystemLocale>$LOCALE</SystemLocale>
      <UILanguage>$LOCALE</UILanguage>
      <UserLocale>$LOCALE</UserLocale>
    </component>
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <TimeZone>$TIMEZONE</TimeZone>
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>$account
      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add">
          <Order>1</Order>
          <CommandLine>cmd /c del /f /q C:\Windows\Panther\unattend*.xml C:\Windows\Panther\autounattend*.xml</CommandLine>
          <Description>Unattend mit Klartext-Passwort entfernen</Description>
        </SynchronousCommand>
      </FirstLogonCommands>
    </component>
  </settings>
</unattend>
XML
}

build_unattend_iso() {
  local user="" pass="" work
  if [[ -f $CRED_FILE ]]; then
    user=$(sed -n 's/^vm_user=//p' "$CRED_FILE" | head -1)
    pass=$(sed -n 's/^vm_password=//p' "$CRED_FILE" | head -1)
  fi
  if [[ -z $user && -t 0 ]]; then
    read -rp  "Lokales Windows-Konto (leer = in OOBE manuell): " user
    [[ -n $user ]] && { read -rsp "Passwort: " pass; echo; }
  fi
  [[ $user == *@* ]] && die "Kein Microsoft-/Siemens-Konto hier - nur ein lokales Konto."
  work=$(mktemp -d); trap 'rm -rf "$work"' RETURN
  emit_unattend "$user" "$pass" > "$work/autounattend.xml"
  xmllint --noout "$work/autounattend.xml" || die "autounattend.xml nicht wohlgeformt."
  R xorriso -as mkisofs -quiet -J -r -V UNATTEND -o "$UNATTEND_ISO" "$work/autounattend.xml"
  R chmod 0600 "$UNATTEND_ISO"
  rm -rf "$work"; trap - RETURN
  log "Unattend-ISO gebaut (lokales Konto: ${user:-manuell})."
}

build_fix_iso() {
  local work user pass
  [[ -d $FIX_DIR ]] || die "Fix-ISO-Vorlagen fehlen: $FIX_DIR"
  command -v xorriso >/dev/null || die "xorriso fehlt."
  work=$(mktemp -d); trap 'rm -rf "$work"' RETURN
  R cp -a "$FIX_DIR/." "$work/"
  if [[ -f "$work/unattended/autounattend.xml" ]]; then
    user=$(sed -n 's/^vm_user=//p' "$CRED_FILE" 2>/dev/null | head -1 || true)
    pass=$(sed -n 's/^vm_password=//p' "$CRED_FILE" 2>/dev/null | head -1 || true)
    sed -i "s/__VM_USER__/$user/g; s/__VM_PASSWORD__/$pass/g" "$work/unattended/autounattend.xml"
  fi
  while IFS= read -r f; do
    sed -i 's/$/\r/' "$f"
    LC_ALL=C grep -P '[^\x00-\x7F]' "$f" >/dev/null && die "Nicht-ASCII in Fix-Datei: $f"
  done < <(find "$work" -type f \( -name '*.cmd' -o -name '*.ps1' \))
  R xorriso -as mkisofs -quiet -J -r -V WIN11_FIX -o "$FIX_ISO" "$work"
  R chmod 0600 "$FIX_ISO"
  rm -rf "$work"; trap - RETURN
  log "Fix-ISO gebaut: $FIX_ISO"
}

# ============================ VORLAGE: Domain-XML =============================
emit_xml() {
  local iso_boot="" disk_boot="<boot order='1'/>" install_media="" virtio_media="" unattend=""
  [[ $BOOT_FROM_ISO == 1 ]] && { iso_boot="<boot order='1'/>"; disk_boot="<boot order='2'/>"; }
  [[ $LINK == up || $LINK == down ]] || die "WIN11_LINK muss up|down sein."
  [[ $ATTACH_INSTALL_MEDIA == 1 && -f $WIN_ISO ]] && install_media="
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='$WIN_ISO'/>
      <target dev='sdb' bus='sata'/>
      <readonly/>
      $iso_boot
    </disk>"
  [[ $ATTACH_VIRTIO_MEDIA == 1 && -f $VIRTIO_ISO ]] && virtio_media="
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='$VIRTIO_ISO'/>
      <target dev='sdc' bus='sata'/>
      <readonly/>
    </disk>"
  [[ $ATTACH_INSTALL_MEDIA == 1 && -f $UNATTEND_ISO ]] && unattend="
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='$UNATTEND_ISO'/>
      <target dev='sdd' bus='sata'/>
      <readonly/>
    </disk>"
  cat <<XML
<domain type='kvm'>
  <name>$VM</name>
  <uuid>$UUID</uuid>
  <memory unit='MiB'>$RAM_MIB</memory>
  <currentMemory unit='MiB'>$RAM_MIB</currentMemory>
  <vcpu placement='static'>$VCPUS</vcpu>
  <memoryBacking>
    <hugepages>
      <page size='2048' unit='KiB'/>
    </hugepages>
  </memoryBacking>

  <sysinfo type='smbios'>
    <system>
      <entry name='manufacturer'>$SMBIOS_MANUFACTURER</entry>
      <entry name='product'>$SMBIOS_PRODUCT</entry>
      <entry name='serial'>$SMBIOS_SERIAL</entry>
    </system>
  </sysinfo>

  <os>
    <type arch='x86_64' machine='$MACHINE'>hvm</type>
    <loader readonly='yes' secure='yes' type='pflash' format='raw'>$OVMF_CODE</loader>
    <nvram template='$OVMF_VARS_TPL' templateFormat='raw' format='raw'>$NVRAM</nvram>
    <smbios mode='sysinfo'/>
    <bootmenu enable='yes' timeout='3000'/>
  </os>

  <features>
    <acpi/>
    <apic/>
    <hyperv mode='custom'>
      <relaxed state='on'/>
      <vapic state='on'/>
      <spinlocks state='on' retries='8191'/>
      <vpindex state='on'/>
      <runtime state='on'/>
      <synic state='on'/>
      <stimer state='on'/>
      <frequencies state='on'/>
      <tlbflush state='on'/>
      <ipi state='on'/>
    </hyperv>
    <vmport state='off'/>
    <smm state='on'/>
  </features>

  <cpu mode='host-passthrough' check='none' migratable='off'>
    <topology sockets='1' dies='1' clusters='1' cores='$VCPUS' threads='1'/>
    <feature policy='disable' name='vmx'/>
  </cpu>

  <clock offset='localtime'>
    <timer name='rtc' tickpolicy='catchup'/>
    <timer name='pit' tickpolicy='delay'/>
    <timer name='hpet' present='no'/>
    <timer name='hypervclock' present='yes'/>
  </clock>

  <on_poweroff>destroy</on_poweroff>
  <on_reboot>destroy</on_reboot>
  <on_crash>preserve</on_crash>
  <pm>
    <suspend-to-mem enabled='no'/>
    <suspend-to-disk enabled='no'/>
  </pm>

  <devices>
    <emulator>/usr/bin/qemu-system-x86_64</emulator>

    <!-- SATA: ohne Treiber im Setup sichtbar. virtio-scsi erst nach Autopilot. -->
    <disk type='block' device='disk'>
      <driver name='qemu' type='raw' cache='none' io='io_uring' discard='unmap' detect_zeroes='unmap'/>
      <source dev='/dev/zvol/$ZVOL'/>
      <target dev='sda' bus='sata'/>
      <serial>$DISK_SERIAL</serial>
      $disk_boot
    </disk>
    $install_media$virtio_media$unattend
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='$FIX_ISO'/>
      <target dev='sde' bus='sata'/>
      <readonly/>
    </disk>

    <controller type='sata' index='0'/>
    <controller type='scsi' index='0' model='virtio-scsi'/>
    <controller type='usb' index='0' model='qemu-xhci' ports='15'/>
    <controller type='virtio-serial' index='0'/>

    <!-- e1000e: laeuft ohne Treiber in der OOBE. Link steuert Autopilot. -->
    <interface type='network'>
      <mac address='$MAC'/>
      <source network='default'/>
      <model type='e1000e'/>
      <link state='$LINK'/>
    </interface>

    <tpm model='tpm-crb'>
      <backend type='emulator' version='2.0' persistent_state='yes'/>
    </tpm>

    <channel type='spicevmc'>
      <target type='virtio' name='com.redhat.spice.0'/>
    </channel>
    <input type='tablet' bus='usb'/>
    <graphics type='spice' autoport='yes'>
      <listen type='address'/>
      <image compression='off'/>
      <streaming mode='off'/>
    </graphics>
    <video>
      <model type='qxl' ram='65536' vram='65536' vgamem='16384' heads='1' primary='yes'/>
    </video>
    <sound model='ich9'/>
    <audio id='1' type='spice'/>
    <redirdev bus='usb' type='spicevmc'/>
    <redirdev bus='usb' type='spicevmc'/>

    <watchdog model='itco' action='none'/>
    <memballoon model='none'/>
    <rng model='virtio'>
      <backend model='random'>/dev/urandom</backend>
    </rng>
  </devices>
</domain>
XML
}

# ============================ VERIFY (harte Sperre) ===========================
cmd_verify() {
  local x ok=1 keys src
  x=$(v dumpxml --inactive "$VM") || die "VM nicht definiert."
  q()   { xmllint --xpath "$1" - <<<"$x" 2>/dev/null || true; }
  chk() { if [[ $3 == "$2" ]]; then printf '  \033[32mOK  \033[0m %-18s %s\n' "$1" "$3"
          else printf '  \033[31mFAIL\033[0m %-18s soll=%s ist=%s\n' "$1" "$2" "${3:-<leer>}"; ok=0; fi; }
  log "verify $VM"
  chk uuid           "$UUID"                "$(q 'string(/domain/uuid)')"
  chk mac            "$MAC"                 "$(q 'string(//interface/mac/@address)')"
  chk smbios-manuf   "$SMBIOS_MANUFACTURER" "$(q "string(//sysinfo/system/entry[@name='manufacturer'])")"
  chk smbios-product "$SMBIOS_PRODUCT"      "$(q "string(//sysinfo/system/entry[@name='product'])")"
  chk smbios-serial  "$SMBIOS_SERIAL"       "$(q "string(//sysinfo/system/entry[@name='serial'])")"
  chk smbios-mode    sysinfo                "$(q 'string(/domain/os/smbios/@mode)')"
  chk disk-serial    "$DISK_SERIAL"         "$(q "string(//disk[@device='disk']/serial)")"
  chk disk-bus       sata                   "$(q "string(//disk[@device='disk']/target/@bus)")"
  chk loader         "$OVMF_CODE"           "$(q 'normalize-space(/domain/os/loader)')"
  chk loader-secure  yes                    "$(q 'string(/domain/os/loader/@secure)')"
  chk nvram-template "$OVMF_VARS_TPL"       "$(q 'string(/domain/os/nvram/@template)')"
  chk fw-autoselect  0                      "$(q 'count(/domain/os/firmware)+count(/domain/os[@firmware])')"
  chk smm            on                     "$(q 'string(//features/smm/@state)')"
  chk avic           0                      "$(q 'count(//hyperv/avic)')"
  for h in synic stimer tlbflush ipi; do chk "hyperv-$h" on "$(q "string(//hyperv/$h/@state)")"; done
  chk tpm-persistent yes                    "$(q 'string(//tpm/backend/@persistent_state)')"
  chk nic            e1000e                 "$(q 'string(//interface/model/@type)')"
  chk watchdog       none                   "$(q 'string(//watchdog/@action)')"
  chk on_reboot      destroy               "$(q 'string(/domain/on_reboot)')"
  chk on_crash       preserve               "$(q 'string(/domain/on_crash)')"
  chk rng            virtio                 "$(q 'string(//rng/@model)')"
  chk video          qxl                    "$(q 'string(//video/model/@type)')"
  chk memory-kib     33554432              "$(q 'string(/domain/memory)')"
  chk vcpu-count     12                     "$(q 'number(/domain/vcpu)')"
  chk hugepages-2m   1                      "$(q "count(/domain/memoryBacking/hugepages/page[@size='2048' and @unit='KiB'])")"
  chk cpu-mode       host-passthrough       "$(q 'string(/domain/cpu/@mode)')"
  chk nested-vmx     1                      "$(q "count(/domain/cpu/feature[@name='vmx' and @policy='disable'])")"
  chk libosinfo      0                      "$(grep -c libosinfo <<<"$x" || true)"
  chk fix-iso        "$FIX_ISO"             "$(q "string(//disk[@device='cdrom']/target[@dev='sde']/../source/@file)")"

  src=$OVMF_VARS_TPL; [[ -f $NVRAM ]] && src=$NVRAM
  keys=$(R virt-fw-vars -i "$src" --print --verbose 2>/dev/null || true)
  for k in PK KEK db; do chk "nvram-$k" yes "$(grep -q "^name=$k " <<<"$keys" && echo yes || echo no)"; done
  chk winca-2023 yes "$(grep -qi 'Windows UEFI CA 2023' <<<"$keys" && echo yes || echo no)"
  chk kek-2023   yes "$(grep -qi 'KEK 2K CA 2023'      <<<"$keys" && echo yes || echo no)"

  ((ok)) || die "verify FEHLGESCHLAGEN - kein Start."
  log "verify GRUEN ($(state))."
}

# ============================ BEFEHLE =========================================
define_domain() {
  local x; x=$(mktemp); trap 'rm -f "$x"' RETURN
  emit_xml > "$x"
  xmllint --noout "$x" || die "Domain-XML nicht wohlgeformt."
  v define "$x" >/dev/null
  rm -f "$x"; trap - RETURN
  log "Domain aus Vorlage definiert."
}

cmd_rebuild() {
  [[ ${1:-} == --force ]] || die "rebuild zerstoert ZVOL, NVRAM, vTPM und Snapshots - nur mit --force."
  host_setup

  log "Entferne alte VM."
  if [[ $(state) != absent ]]; then
    [[ $(state) == "shut off" ]] || v destroy "$VM" >/dev/null || true
    v undefine "$VM" --nvram --tpm >/dev/null 2>&1 || v undefine "$VM" --nvram >/dev/null || true
  fi
  R rm -rf "$NVRAM" "$SWTPM_DIR" "$SNAP_DIR"
  zfs list -H -o name "$ZVOL" &>/dev/null && R zfs destroy -r -f "$ZVOL"
  zfs list -H -o name "$POOL/vms" &>/dev/null || R zfs create -o mountpoint=none -o atime=off "$POOL/vms"
  R zfs create -V "$VOLSIZE" -b "$VOLBLOCK" -o compression=zstd-1 -o sync=standard \
    -o primarycache=metadata -o volmode=dev "$ZVOL"

  build_unattend_iso
  build_fix_iso
  ATTACH_INSTALL_MEDIA=1
  ATTACH_VIRTIO_MEDIA=1
  BOOT_FROM_ISO=1
  define_domain
  cmd_verify
  v start "$VM" >/dev/null
  for _ in 1 2 3 4 5 6; do sleep 2; v send-key "$VM" KEY_ENTER >/dev/null 2>&1 || true; done  # "Press any key"
  log "Setup laeuft. Netz: $LINK."
  cat <<'NEXT'

  Naechste Schritte
  1. Setup laeuft automatisch bis zum Desktop (lokales Konto, Netz AUS).
  2. ./win11-vm.sh link up          -> in Windows: virtio-win-guest-tools.exe (CD),
                                       Windows Update bis nichts mehr kommt
  3. In Windows pruefen (beides muss "nicht gefunden" melden):
       dir C:\Windows\WinSxS\pending.xml
       reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
  4. ./win11-vm.sh media eject ; Windows herunterfahren ; ./win11-vm.sh snapshot pre-reset ; ./win11-vm.sh start
  5. Windows: PC zuruecksetzen -> Alles entfernen -> Lokale Neuinstallation
  6. OOBE: Shift+F10, Pruefung aus 3. ; herunterfahren ; snapshot pre-autopilot ; start
  7. Siemens-Konto -> Autopilot.   Fehlschlag: ./win11-vm.sh rollback pre-autopilot
NEXT
}

cmd_start()  { cmd_verify; v start "$VM" >/dev/null; log "gestartet."; }
cmd_fixiso() { build_fix_iso; v change-media "$VM" sde "$FIX_ISO" --config --force >/dev/null; [[ $(state) == running ]] && v change-media "$VM" sde "$FIX_ISO" --live --force >/dev/null || true; log "Fix-ISO eingebunden."; }
cmd_define() { [[ $(state) == running ]] && die "VM laeuft."; define_domain; cmd_verify; }

cmd_link() {
  [[ ${1:-} == up || ${1:-} == down ]] || die "link up|down"
  v domif-setlink "$VM" "$MAC" "$1" --config >/dev/null 2>&1 || true
  [[ $(state) == running ]] && v domif-setlink "$VM" "$MAC" "$1" >/dev/null
  log "Netzlink: $1"
}

cmd_media() {
  [[ ${1:-} == eject ]] || die "media eject"
  local flags=(--config); [[ $(state) == running ]] && flags+=(--live)
  v change-media "$VM" sdb --eject "${flags[@]}" >/dev/null 2>&1 || true
  v detach-disk  "$VM" sdd "${flags[@]}"         >/dev/null 2>&1 || true
  R shred -u "$UNATTEND_ISO" 2>/dev/null || R rm -f "$UNATTEND_ISO"
  log "Windows-ISO ausgeworfen, Unattend-ISO entfernt und geloescht. virtio-CD bleibt."
}

cmd_snapshot() {
  local n=${1:-list}
  if [[ $n == list ]]; then
    zfs list -H -t snapshot -o name,creation,used "$ZVOL" 2>/dev/null | sed "s#^$ZVOL@##"; return
  fi
  need_off
  [[ -d $SWTPM_DIR && -f $NVRAM ]] || die "NVRAM/vTPM fehlen - VM noch nie gestartet?"
  zfs list -H -o name "$ZVOL@$n" &>/dev/null && die "Snapshot $n existiert bereits."
  R install -d -m 0700 "$SNAP_DIR/$n"
  R zfs snapshot "$ZVOL@$n"
  R cp -a "$NVRAM" "$SNAP_DIR/$n/VARS.fd"
  R cp -a "$SWTPM_DIR" "$SNAP_DIR/$n/swtpm"
  log "Snapshot $n: ZVOL + NVRAM + vTPM."
}

cmd_rollback() {
  local n=${1:?rollback <name>}
  need_off
  [[ -d $SNAP_DIR/$n ]] || die "Kein Snapshot $n."
  R zfs rollback -r "$ZVOL@$n"
  R cp -a "$SNAP_DIR/$n/VARS.fd" "$NVRAM"
  R rm -rf "$SWTPM_DIR"; R cp -a "$SNAP_DIR/$n/swtpm" "$SWTPM_DIR"
  log "Rollback auf $n (ZVOL + NVRAM + vTPM)."
}

case "${1:-help}" in
  setup)    host_setup ;;
  rebuild)  shift; cmd_rebuild "$@" ;;
  define)   cmd_define ;;
  verify)   cmd_verify ;;
  start)    cmd_start ;;
  fixiso)   cmd_fixiso ;;
  link)     shift; cmd_link "$@" ;;
  media)    shift; cmd_media "$@" ;;
  snapshot) shift; cmd_snapshot "$@" ;;
  rollback) shift; cmd_rollback "$@" ;;
  xml)      emit_xml ;;
  unattend) emit_unattend "${2:-beispiel}" "***" ;;
  *) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' ;;
esac

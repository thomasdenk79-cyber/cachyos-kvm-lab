#!/usr/bin/env bash
# 11-seed-win11.sh - erzeugt win11-seed.iso mit autounattend.xml + post.ps1.
set -euo pipefail
cd "$(dirname "$0")"; source ./env.sh
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/autounattend.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unpackages" xmlns:w2="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:v="urn:schemas-microsoft-com:unpackages/2008/unattended/winpe">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <DiskConfiguration>
        <WillWipeDisk>true</WillWipeDisk>
        <Disk w2:pass="windowsPE" willWipe="true">
          <DiskID>0</DiskID>
          <CreatePartitions>
            <CreatePartition w2:pass="windowsPE" order="1">
              <Order>1</Order><Size>500</Size><Type>EFI</Type>
            </CreatePartition>
            <CreatePartition w2:pass="windowsPE" order="2">
              <Order>2</Order><Size>16</Size><Type>MSR</Type>
            </CreatePartition>
            <CreatePartition w2:pass="windowsPE" order="3">
              <Order>3</Order><ExtendPartition>true</ExtendPartition><Type>Primary</Type>
            </CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition w2:pass="windowsPE" order="1">
              <Order>1</Order><PartitionID>1</PartitionID><Format>FAT32</Format><Label>System</Label>
            </ModifyPartition>
            <ModifyPartition w2:pass="windowsPE" order="2">
              <Order>2</Order><PartitionID>2</PartitionID>
            </ModifyPartition>
            <ModifyPartition w2:pass="windowsPE" order="3">
              <Order>3</Order><PartitionID>3</PartitionID><Format>NTFS</Format><Label>Windows</Label><Letter>C</Letter>
            </ModifyPartition>
          </ModifyPartitions>
        </Disk>
      </DiskConfiguration>
      <ImageInstall>
        <OSImage>
          <InstallFrom>
            <MetaData w2:attribute="Name" w2:value="Windows 11 Pro" />
          </InstallFrom>
          <InstallTo><DiskID>0</DiskID><PartitionID>3</PartitionID></InstallTo>
        </OSImage>
      </ImageInstall>
      <UserData>
        <AcceptEula>true</AcceptEula>
      </UserData>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <NetworkLocation>Work</NetworkLocation>
        <SkipMachineOOBE>true</SkipMachineOOBE>
        <SkipUserOOBE>true</SkipUserOOBE>
      </OOBE>
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount w2:action="Add">
            <Name>vmadmin</Name>
            <Group>Administrators</Group>
            <LogonCount>1</LogonCount>
            <Password>
              <Value>LABPWPLACEHOLDER</Value>
              <PlainText>true</PlainText>
            </Password>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
      <AutoLogon>
        <Enabled>true</Enabled>
        <Username>vmadmin</Username>
        <Password><Value>LABPWPLACEHOLDER</Value><PlainText>true</PlainText></Password>
        <LogonCount>999</LogonCount>
      </AutoLogon>
      <FirstLogonCommands>
        <SynchronousCommand w2:pass="oobeSystem" order="1">
          <Order>1</Order>
          <CommandLine>cmd /c powershell -NoProfile -ExecutionPolicy Bypass -Command "$c=Get-CimInstance Win32_CDROMDrive|?{$_.Drive -match '^[D-Z]:'}|%{$_.Drive.Substring(0,2)+':'};foreach($d in $c){if(Test-Path ($d+'\post.ps1')){New-Item -ItemType Directory C:\Lab -Force|Out-Null;Copy-Item ($d+'\post.ps1') C:\Lab\ -Force;Copy-Item ($d+'\vm.pass') C:\Lab\ -Force;break}};schtasks /create /tn LABPOST /tr 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\Lab\post.ps1' /sc onstart /ru SYSTEM /rl HIGHEST /f|Out-Null;schtasks /run /tn LABPOST" </CommandLine>
          <Description>Copy and start LABPOST</Description>
        </SynchronousCommand>
      </FirstLogonCommands>
    </component>
    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <InputLocale>de-DE</InputLocale>
      <SystemLocale>de-DE</SystemLocale>
      <UserLocale>de-DE</UserLocale>
      <UILanguage>de-DE</UILanguage>
    </component>
  </settings>
</unattend>
XML

cat > "$TMP/post.ps1" <<'PS1'
$ErrorActionPreference='SilentlyContinue'
Start-Transcript -Path C:\Lab\post.log -Append | Out-Null
# RDP aktivieren
Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' fDenyTSConnections 0
Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' UserAuthentication 1
Set-Service TermService -StartupType Automatic; Start-Service TermService
NetSh Advfirewall firewall set rule group='Benutzerdesktopfreigabe (Remotedesktop)' new enable=yes | Out-Null
NetSh Advfirewall firewall set rule group='Remote Desktop' new enable=yes | Out-Null
# SSH-Server
if (-not (Get-WindowsCapability -Online -Name OpenSSH.Server* | ?{$_.State -eq 'Installed'})) {
  Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
}
Set-Service sshd -StartupType Automatic; Start-Service sshd
if (-not (NetSh Advfirewall firewall show rule name='lab-ssh' | Select-String 'lab-ssh')) {
  New-NetFirewallRule -Name lab-ssh -DisplayName 'lab-ssh' -Group '@firewallapi.dll,-46501' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
}
# Pubkey des Hosts erlauben
$pub = Get-Content C:\Lab\authorized_keys.pub -ErrorAction SilentlyContinue
if ($pub) { $a="C:\ProgramData\ssh\administrators_authorized_keys"; $acl=Get-Acl $a -EA SilentlyContinue; Set-Content -Path $a -Value $pub -Force }
# VirtIO-Treiber + QEMU Guest Agent
$cds = Get-CimInstance Win32_CDROMDrive | %{$_.Drive.Substring(0,2)}
$vd = $cds | ?{Test-Path "${_}\guest-agent\qemu-ga-x86_64.msi"} | Select-Object -First 1
if ($vd) {
  pnputil /add-driver "${vd}\NetKVM\w10\amd64\netkvm.inf" /install | Out-Null
  pnputil /add-driver "${vd}\vioscsi\w10\amd64\vioscsi.inf" /install | Out-Null
  pnputil /add-driver "${vd}\viostor\w10\amd64\viostor.inf" /install | Out-Null
  pnputil /add-driver "${vd}\Balloon\w10\amd64\balloon.inf" /install | Out-Null
  pnputil /add-driver "${vd}\fwcfg\w10\fwcfg.inf" /install | Out-Null
  pnputil /add-driver "${vd}\vioserial\w10\amd64\vioser.inf" /install | Out-Null
  Start-Process msiexec -ArgumentList "/i","${vd}\guest-agent\qemu-ga-x86_64.msi","/qn","/norestart" -Wait
  Set-Service 'qemu-ga' -StartupType Automatic -EA SilentlyContinue; Start-Service 'qemu-ga' -EA SilentlyContinue
  Set-Service 'QEMU Guest Agent VSS Provider' -StartupType Automatic -EA SilentlyContinue
}
# Updates bis zum Anschlag
if (-not (Get-Module -ListAvailable PSWindowsUpdate)) {
  Set-PSRepository PSGallery -InstallationPolicy Trusted
  Install-Module PSWindowsUpdate -Force -AllowClobber -SkipPublisherCheck
}
Import-Module PSWindowsUpdate
$more = Get-WindowsUpdate -AcceptAll | Measure-Object
if ($more.Count -gt 0) {
  Install-WindowsUpdate -AcceptAll -AutoReboot
  exit 0
}
# Abschluss
powercfg /change standby-timeout-ac 0; powercfg /change monitor-timeout-ac 5
cmdkey /generic:TERMSRV/* /user:vmadmin /pass:"$(Get-Content C:\Lab\vm.pass)" | Out-Null
New-Item C:\Lab\done -ItemType File -Force | Out-Null
schtasks /delete /tn LABPOST /f | Out-Null
Stop-Transcript
PS1

PW=$(get_pass)
sed -i "s/LABPWPLACEHOLDER/$PW/g" "$TMP/autounattend.xml"
printf '%s' "$PW" > "$TMP/vm.pass"
cp "$SSH_KEY.pub" "$TMP/authorized_keys.pub"
rm -f "$LAB_SEED/win11-seed.iso"
xorriso -as mkisofs -o "$LAB_SEED/win11-seed.iso" -volid WINSEED -r "$TMP" >/dev/null
ls -l "$LAB_SEED/win11-seed.iso"; echo "win11-seed.iso OK"

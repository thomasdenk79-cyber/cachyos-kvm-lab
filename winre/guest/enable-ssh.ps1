# Run as administrator. Enables Windows OpenSSH server for libvirt NAT only.
$ErrorActionPreference = 'Stop'

# Install the user's public key for the signed-in Windows account. This file
# contains public material only; never add a private key to the repository.
# Keep authorized_keys entries on one line in OpenSSH format. RFC4716/SSH2
# exports with BEGIN/END headers and wrapped base64 are not valid here.
$authorizedKey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFcoxC1xl9wlbxOVDJxHmLm6uv5d+friOetfYk21jw0X z000g9hu@2013-11-15'
$sshDirectory = Join-Path $env:USERPROFILE '.ssh'
$authorizedKeys = Join-Path $sshDirectory 'authorized_keys'
New-Item -ItemType Directory -Path $sshDirectory -Force | Out-Null
$existingKeys = if (Test-Path $authorizedKeys) {
    Get-Content -Path $authorizedKeys
} else {
    @()
}
if ($authorizedKey -notin $existingKeys) {
    Add-Content -Path $authorizedKeys -Value $authorizedKey -Encoding ascii
}
icacls.exe $sshDirectory /inheritance:r /grant:r "$($env:USERNAME):(OI)(CI)F" 'SYSTEM:(OI)(CI)F' | Out-Null
icacls.exe $authorizedKeys /inheritance:r /grant:r "$($env:USERNAME):F" 'SYSTEM:F' | Out-Null

# Allow local administrator accounts to receive a full token over SSH.
# The SSH firewall rule below remains restricted to the libvirt NAT network.
New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
    -Name LocalAccountTokenFilterPolicy -PropertyType DWord -Value 1 -Force | Out-Null

$cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0'
if ($cap.State -ne 'Installed') {
    Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0'
}

Set-Service -Name sshd -StartupType Automatic
Start-Service sshd

$ruleName = 'Win11-SSH-Libvirt'
Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule -ErrorAction SilentlyContinue
New-NetFirewallRule -Name $ruleName -DisplayName 'Win11 SSH from libvirt' `
    -Direction Inbound -Protocol TCP -LocalPort 22 `
    -RemoteAddress 192.168.122.0/24 -Action Allow -Profile Any

Get-Service sshd | Format-Table Status, StartType, Name
Get-NetTCPConnection -LocalPort 22 -State Listen | Format-Table LocalAddress, LocalPort, State
Write-Host "Installed public key in $authorizedKeys for $env:USERNAME."
Write-Host 'OpenSSH server is enabled on TCP 22 for libvirt NAT.'

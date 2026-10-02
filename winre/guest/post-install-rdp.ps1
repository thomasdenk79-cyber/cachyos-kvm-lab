# Run as administrator. Safe to run repeatedly; no cleartext passwords.
$ErrorActionPreference = 'Stop'

$regPath = Join-Path $PSScriptRoot '..\rdp-enable.reg'
if (Test-Path $regPath) {
    & reg.exe import $regPath
}

# RDP-Dienst aktivieren und sofort starten.
Set-Service -Name TermService -StartupType Automatic
Start-Service -Name TermService

# Explicit language-independent rule for the libvirt NAT network only.
$ruleName = 'Win11-RDP-Libvirt'
Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule -ErrorAction SilentlyContinue
New-NetFirewallRule -Name $ruleName -DisplayName 'Win11 RDP from libvirt' `
    -Direction Inbound -Protocol TCP -LocalPort 3389 `
    -RemoteAddress 192.168.122.0/24 -Action Allow -Profile Any

# Vorhandene Microsoft-RDP-Regeln ebenfalls aktivieren.
Get-NetFirewallRule -Name 'RemoteDesktop-*' -ErrorAction SilentlyContinue |
    Enable-NetFirewallRule

# NLA erzwingen.
Set-ItemProperty `
    'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
    -Name UserAuthentication -Type DWord -Value 1

Write-Host "`n--- RDP status ---"
Get-Service TermService | Format-Table Status, StartType, Name
Get-NetFirewallRule -Name $ruleName | Format-Table Name, Enabled, Action, Profile
Get-NetTCPConnection -LocalPort 3389 -State Listen | Format-Table LocalAddress, LocalPort, State, OwningProcess
Write-Host "RDP configuration complete."

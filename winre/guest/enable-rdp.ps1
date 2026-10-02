# Run in an elevated Windows PowerShell. Safe to run repeatedly.
$ErrorActionPreference = 'Stop'
$reg = Join-Path $PSScriptRoot '..\rdp-enable.reg'
reg.exe import $reg

Set-Service -Name TermService -StartupType Automatic
Start-Service -Name TermService

# Rule names are language independent; DisplayGroup is localized on Windows.
$rules = Get-NetFirewallRule -Name 'RemoteDesktop-*' -ErrorAction SilentlyContinue
if (-not $rules) {
    New-NetFirewallRule -Name 'RemoteDesktop-TCP-In' -DisplayName 'Remote Desktop TCP 3389' `
      -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow -Profile Domain,Private
} else {
    $rules | Enable-NetFirewallRule
}

Get-NetTCPConnection -LocalPort 3389 -State Listen
Write-Host 'RDP is enabled and listening on TCP 3389.'

$ErrorActionPreference = 'Continue'
Get-NetFirewallRule | Where-Object { $_.DisplayGroup -match 'Remote|Remotedesktop' } | Enable-NetFirewallRule
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
Set-Service -Name TermService -StartupType Automatic
Start-Service -Name TermService
# Do not install Windows updates while OOBE/CloudExperienceHost is active.
# Servicing the OOBE binaries here can leave a pending reboot with an
# unusable EFI/BCD state. Run updates only after OOBE and Intune enrollment.
$ga = Join-Path $PSScriptRoot 'guest-agent\qemu-ga-x86_64.msi'
if (Test-Path $ga) { Start-Process msiexec.exe -ArgumentList "/i `"$ga`" /qn /norestart" -Wait }
# Optional winget installs are intentionally deferred until after OOBE/Intune.

New-Item -ItemType File -Force "$env:ProgramData\Siemens-Win11-PostInstall.done" | Out-Null

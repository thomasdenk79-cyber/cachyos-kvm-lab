@echo off
set W=%SystemRoot%
reg add HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard /v EnableVirtualizationBasedSecurity /t REG_DWORD /d 1 /f
reg add HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\SystemGuard /v Enabled /t REG_DWORD /d 0 /f
bcdedit /set hypervisorlaunchtype auto
echo VBS test configured. Reboot manually and record the result.
pause

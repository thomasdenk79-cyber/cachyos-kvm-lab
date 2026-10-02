@echo off
setlocal
set W=
for %%d in (C D E F G H) do if exist %%d:\Windows\System32\config\SYSTEM set W=%%d:
if "%W%"=="" exit /b 10
mountvol S: /S >nul 2>&1
set LOG=%W%\winre-test-signedchain.log
reg load HKLM\OFF %W%\Windows\System32\config\SYSTEM > "%LOG%" 2>&1
echo ===== BEFORE ===== >> "%LOG%"
reg query HKLM\OFF\ControlSet001\Control\DeviceGuard /s >> "%LOG%" 2>&1
for %%c in (ControlSet001 ControlSet002) do (
 reg add HKLM\OFF\%%c\Control\DeviceGuard\Scenarios\SystemGuard /v Enabled /t REG_DWORD /d 0 /f
 reg add HKLM\OFF\%%c\Control\DeviceGuard /v RequireMicrosoftSignedBootChain /t REG_DWORD /d 1 /f
 reg add HKLM\OFF\%%c\Control\DeviceGuard /v EnableVirtualizationBasedSecurity /t REG_DWORD /d 0 /f
)
reg unload HKLM\OFF >> "%LOG%" 2>&1
bcdedit /store S:\EFI\Microsoft\Boot\BCD /set {default} hypervisorlaunchtype off >> "%LOG%" 2>&1
echo ===== AFTER ===== >> "%LOG%"
bcdedit /store S:\EFI\Microsoft\Boot\BCD /enum {default} >> "%LOG%" 2>&1
echo Test A configured. Reboot manually. Log: %LOG%
endlocal

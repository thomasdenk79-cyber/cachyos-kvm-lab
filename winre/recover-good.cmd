@echo off
setlocal
set W=
for %%d in (C D E F G H) do if exist %%d:\Windows\System32\config\SYSTEM set W=%%d:
if "%W%"=="" echo Windows volume not found.&exit /b 10
mountvol S: /S >nul 2>&1
set LOG=%W%\winre-recover-good.log
reg load HKLM\OFF %W%\Windows\System32\config\SYSTEM > "%LOG%" 2>&1
(
 echo ===== SELECT =====
 reg query HKLM\OFF\Select
 echo ===== BEFORE =====
 reg query HKLM\OFF\ControlSet001\Control\DeviceGuard /s
 reg query HKLM\OFF\ControlSet002\Control\DeviceGuard /s
) >> "%LOG%" 2>&1
for %%c in (ControlSet001 ControlSet002) do (
 reg add HKLM\OFF\%%c\Control\DeviceGuard\Scenarios\SystemGuard /v Enabled /t REG_DWORD /d 0 /f
 reg add HKLM\OFF\%%c\Control\DeviceGuard /v RequireMicrosoftSignedBootChain /t REG_DWORD /d 0 /f
 reg add HKLM\OFF\%%c\Control\DeviceGuard /v EnableVirtualizationBasedSecurity /t REG_DWORD /d 0 /f
)
(
 echo ===== AFTER =====
 reg query HKLM\OFF\ControlSet001\Control\DeviceGuard /s
 reg query HKLM\OFF\ControlSet002\Control\DeviceGuard /s
) >> "%LOG%" 2>&1
reg unload HKLM\OFF >> "%LOG%" 2>&1
bcdedit /store S:\EFI\Microsoft\Boot\BCD /set {default} hypervisorlaunchtype off >> "%LOG%" 2>&1
bcdedit /store S:\EFI\Microsoft\Boot\BCD /set {default} recoveryenabled yes >> "%LOG%" 2>&1
bcdedit /store S:\EFI\Microsoft\Boot\BCD /deletevalue {default} bootstatuspolicy >> "%LOG%" 2>&1
bcdedit /store S:\EFI\Microsoft\Boot\BCD /set {default} bootlog no >> "%LOG%" 2>&1
bcdedit /store S:\EFI\Microsoft\Boot\BCD /set {default} sos no >> "%LOG%" 2>&1
bcdedit /store S:\EFI\Microsoft\Boot\BCD /enum {default} >> "%LOG%" 2>&1
echo Known-good baseline applied. Log: %LOG%
endlocal

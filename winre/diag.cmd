@echo off
set W=
for %%d in (C D E F G H I J K L M N O P Q R) do if exist %%d:\Windows\System32\config\SYSTEM set W=%%d:
if not defined W echo Windows not found&pause&exit /b 1
mountvol S: /S >nul 2>&1
set L=%W%\winre-diag.log
> %L% echo ===== DeviceGuard and boot diagnosis =====
reg load HKLM\OFF %W%\Windows\System32\config\SYSTEM >>%L% 2>&1
reg query HKLM\OFF\Select /v Current >>%L% 2>&1
reg query HKLM\OFF\ControlSet001\Control\DeviceGuard /s >>%L% 2>&1
reg query HKLM\OFF\ControlSet001\Control\Lsa /v LsaCfgFlags >>%L% 2>&1
reg unload HKLM\OFF >>%L% 2>&1
bcdedit /store S:\EFI\Microsoft\Boot\BCD /enum all >>%L% 2>&1
if exist %W%\Windows\System32\LogFiles\Srt\SrtTrail.txt type %W%\Windows\System32\LogFiles\Srt\SrtTrail.txt >>%L%
if exist %W%\Windows\WinSxS\pending.xml echo pending.xml PRESENT>>%L%
if not exist %W%\Windows\WinSxS\pending.xml echo pending.xml ABSENT>>%L%
type %L% | more
pause

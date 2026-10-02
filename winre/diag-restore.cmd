@echo off
set W=
for %%d in (C D E F G H) do if exist %%d:\Windows\System32\config\SYSTEM set W=%%d:
mountvol S: /S >nul 2>&1
set L=%W%\winre-diag-restore.log
bcdedit /store S:\EFI\Microsoft\Boot\BCD /set {default} recoveryenabled yes >%L% 2>&1
bcdedit /store S:\EFI\Microsoft\Boot\BCD /deletevalue {default} bootstatuspolicy >>%L% 2>&1
bcdedit /store S:\EFI\Microsoft\Boot\BCD /set {default} bootlog no >>%L% 2>&1
bcdedit /store S:\EFI\Microsoft\Boot\BCD /set {default} sos no >>%L% 2>&1
bcdedit /store S:\EFI\Microsoft\Boot\BCD /enum {default} >>%L% 2>&1
type %L% | more
pause

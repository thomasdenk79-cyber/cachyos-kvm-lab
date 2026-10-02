@echo off
set W=
for %%d in (C D E F G H) do if exist %%d:\Windows\System32\config\SYSTEM set W=%%d:
mountvol S: /S >nul 2>&1
set L=%W%\winre-bcdboot-repair.log
bcdboot %W%\Windows /s S: /f UEFI /v >%L% 2>&1
type %L% | more
pause

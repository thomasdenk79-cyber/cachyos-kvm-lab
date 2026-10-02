@echo off
set L=%SystemRoot%\winre-pending-check.log
> %L% echo ===== pending and reboot state =====
if exist %SystemRoot%\WinSxS\pending.xml (echo pending.xml PRESENT>>%L%) else (echo pending.xml ABSENT>>%L%)
reg query HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending >>%L% 2>&1
type %L%
pause

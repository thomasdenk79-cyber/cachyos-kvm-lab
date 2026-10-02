# Recovery runbook

For `0xc0000001` / automatic repair:

1. Select Troubleshoot, Advanced options, Command Prompt.
2. Find the WIN11_FIX CD and run `<CD>:\recover-good.cmd`.
3. Choose Exit and Continue.
4. After a successful boot, capture the log from the Windows root.

For diagnosis use `<CD>:\diag.cmd`. Use `diag-restore.cmd` only when the
diagnostic BCD flags should be removed. `hypervisorlaunchtype` is intentionally
not changed by that restore script.

WINRE FIX MEDIA (WIN11_FIX)
Run: X:\diag.cmd, X:\diag-restore.cmd, X:\bcdboot-repair.cmd.
For the installed Windows guest, run X:\guest\post-install-rdp.ps1 from an
elevated PowerShell. It imports X:\rdp-enable.reg, enables TermService,
enforces NLA, opens TCP 3389 for the libvirt NAT network and verifies the
listener. The shorter X:\guest\enable-rdp.ps1 remains available as well.
To enable host-to-guest SSH, run X:\guest\enable-ssh.ps1 from an elevated
PowerShell. It installs/starts OpenSSH Server and allows TCP 22 only from
192.168.122.0/24.
The script installs the public key in OpenSSH one-line format. Do not paste an
RFC4716/SSH2 public-key export with BEGIN/END headers into authorized_keys;
convert it to one `ssh-ed25519 ...` line first.
The script also enables full administrator tokens for local administrator SSH
sessions so remote administrative PowerShell commands work. Use a dedicated
strong Windows password; the rule is limited to the private libvirt network.
Scripts find Windows automatically, mount EFI as S:, and write logs to Windows.
The unattend template is under unattend\ and never in the ISO root.

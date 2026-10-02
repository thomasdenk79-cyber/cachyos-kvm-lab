$o = [pscustomobject]@{Serial=(Get-CimInstance Win32_BIOS).SerialNumber; MAC=(Get-CimInstance Win32_NetworkAdapter -Filter "PhysicalAdapter=True" | Where-Object MACAddress | Select-Object -First 1 -Expand MACAddress); Hash='Use Windows hardware hash export or Intune diagnostic'}
$o | Export-Csv C:\autopilot-hash.csv -NoTypeInformation
$o | Format-List

#Requires -RunAsAdministrator
# Backup-Short.ps1 - snapshot this box's config into C:\IR\bk_<host>_<time>, then hash it
# Check a backup later for tampering (lists anything changed or missing):
#   Import-Csv <backup folder>\_manifest.csv | Where-Object { (Get-FileHash $_.Path -EA 0).Hash -ne $_.Hash }
$d    = "C:\IR\bk_$($env:COMPUTERNAME)_$(Get-Date -Format yyyyMMdd_HHmmss)"
$isDC = (Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4

# lock C:\IR to SYSTEM + Administrators before writing anything into it
New-Item C:\IR -ItemType Directory -Force | Out-Null
icacls C:\IR /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" | Out-Null
New-Item $d -ItemType Directory -Force | Out-Null

# run a step, then OK only if its output exists and isn't empty
function Save($name, [scriptblock]$code, $output) {
    $err = ""
    try { & $code | Out-Null } catch { $err = $_.Exception.Message }
    if ((Test-Path $output) -and (Get-ChildItem $output -Recurse -File | Where-Object Length -gt 0)) { Write-Host "OK    $name" -ForegroundColor Green }
    else { Write-Host "FAIL  $name  $err" -ForegroundColor Red }
}

# every box
Save "Services"  { Get-CimInstance Win32_Service | Select-Object Name, State, StartMode, StartName, PathName | Export-Csv "$d\services.csv" -NoTypeInformation } "$d\services.csv"
Save "Tasks"     { schtasks /query /fo csv /v > "$d\tasks.csv" } "$d\tasks.csv"
Save "Shares"    { Get-SmbShare | Get-SmbShareAccess | Export-Csv "$d\shares.csv" -NoTypeInformation } "$d\shares.csv"
Save "Ports"     { Get-NetTCPConnection -State Listen | Select-Object LocalPort, @{n = "Process"; e = { (Get-Process -Id $_.OwningProcess -EA 0).Path } } | Export-Csv "$d\ports.csv" -NoTypeInformation } "$d\ports.csv"
Save "Firewall"  { netsh advfirewall export "$d\firewall.wfw" } "$d\firewall.wfw"
Save "Hosts"     { Copy-Item "$env:windir\System32\drivers\etc\hosts" "$d\hosts" } "$d\hosts"
Save "Registry"  {
    reg export "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" "$d\reg_run.reg" /y
    reg export "HKLM\SYSTEM\CurrentControlSet\Services" "$d\reg_services.reg" /y
} "$d\reg_services.reg"

if (-not $isDC) {
    Save "Local users"  { Get-LocalUser | Select-Object Name, Enabled, PasswordLastSet | Export-Csv "$d\users.csv" -NoTypeInformation } "$d\users.csv"
    Save "Local admins" { net localgroup administrators > "$d\admins.txt" } "$d\admins.txt"
}

if ($isDC) {
    Save "AD users"  { Get-ADUser -Filter * -Properties MemberOf, whenCreated | Select-Object SamAccountName, Enabled, whenCreated, @{n = "Groups"; e = { $_.MemberOf -join ";" } } | Export-Csv "$d\ad_users.csv" -NoTypeInformation } "$d\ad_users.csv"
    Save "GPOs"      { New-Item "$d\gpo" -ItemType Directory | Out-Null; Backup-GPO -All -Path "$d\gpo" } "$d\gpo"
    Save "DNS zones" {
        New-Item "$d\dns" -ItemType Directory | Out-Null
        foreach ($z in Get-DnsServerZone | Where-Object { -not $_.IsAutoCreated -and $_.ZoneType -eq "Primary" -and $_.ZoneName -ne "TrustAnchors" }) {
            $f = "bk_$($z.ZoneName).dns"   # Windows always writes this into System32\dns, so move it after
            Export-DnsServerZone -Name $z.ZoneName -FileName $f
            Move-Item "$env:windir\System32\dns\$f" "$d\dns\" -Force
        }
    } "$d\dns"
}

$appcmd = "$env:windir\System32\inetsrv\appcmd.exe"
if (Test-Path $appcmd) {
    # restore config with:  appcmd restore backup "<name printed at the end>"
    Save "IIS config" { & $appcmd add backup "bk_$(Split-Path $d -Leaf)"; Copy-Item "$env:windir\System32\inetsrv\config" "$d\iis_config" -Recurse } "$d\iis_config"
    Save "IIS files"  { robocopy C:\inetpub "$d\inetpub" /E /XD logs /R:0 /W:0 /NFL /NDL /NJH /NJS } "$d\inetpub"
}

# hash everything so tampering shows up later
Get-ChildItem $d -Recurse -File | Get-FileHash | Select-Object Hash, Path | Export-Csv "$d\_manifest.csv" -NoTypeInformation
Write-Host "`nSaved to $d"
Write-Host "Manifest hash: $((Get-FileHash "$d\_manifest.csv").Hash)  <-- SCREENSHOT THIS" -ForegroundColor Cyan

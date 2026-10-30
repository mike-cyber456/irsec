#Requires -RunAsAdministrator
# Rotate-Short.ps1 - new random passwords for this box's accounts
# (domain accounts on the DC, local accounts everywhere else)
#   .\Rotate-Short.ps1 -Preview                 show who would change
#   .\Rotate-Short.ps1 -Only principal,chiefeng just these
#   .\Rotate-Short.ps1 -Skip pitcrew            everyone but these
#   .\Rotate-Short.ps1 -Yes                     don't ask, just do it (run -Preview first!)
param([string[]]$Only, [string[]]$Skip, [switch]$Preview, [switch]$Yes)
$ErrorActionPreference = "Stop"

# handles both "-Only a,b" styles
$Only = @($Only -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$Skip = @($Skip -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$isDC = (Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4
$never = @("whiteteam", "krbtgt", "ddagentuser", "dd-agent", "Guest", "DefaultAccount", "WDAGUtilityAccount", $env:USERNAME) + $Skip

# 20 random chars from the crypto RNG, no look-alikes, always upper + lower + number
function New-Pw($user) {
    $chars = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # 56 chars
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    do {
        $bytes = New-Object byte[] 64
        $rng.GetBytes($bytes)
        # only use bytes under 224 (= 56 x 4) so every character is equally likely
        $pw = -join ($bytes | Where-Object { $_ -lt 224 } | Select-Object -First 20 | ForEach-Object { $chars[$_ % 56] })
    } until ($pw.Length -eq 20 -and $pw -cmatch "[a-z]" -and $pw -cmatch "[A-Z]" -and $pw -match "\d" -and $pw -notlike "*$user*")
    $pw
}

# who to change
if ($isDC) { Import-Module ActiveDirectory; $accounts = Get-ADUser -Filter * | Select-Object @{n = "Name"; e = { $_.SamAccountName } }, Enabled, SID }
else       { $accounts = Get-LocalUser | Select-Object Name, Enabled, SID }

$targets = @($accounts | Where-Object {
    $_.Enabled -and
    $never -notcontains $_.Name -and
    $_.Name -notmatch "whiteteam|datadog|^dd-?agent" -and
    $_.SID.Value.Split("-")[-1] -notin "501", "502", "503", "504" -and   # built-ins, even if renamed
    ($Only.Count -eq 0 -or $Only -contains $_.Name)
})

Write-Host "Will change: $($targets.Name -join ', ')" -ForegroundColor Cyan
Get-CimInstance Win32_Service | Where-Object { $_.StartName -and $targets.Name -contains ($_.StartName -split "\\")[-1] } |
    ForEach-Object { Write-Warning "Service $($_.Name) runs as $($_.StartName) - update it after, or -Skip that account" }
if ($Preview -or $targets.Count -eq 0) { return }
if (-not $Yes) {
    $answer = Read-Host "Type YES to continue"
    # "$answer" so an empty/null answer doesn't crash; -ne ignores upper/lower case
    if ("$answer".Trim() -ne "YES") { Write-Host "Cancelled - got '$answer', expected YES. Nothing changed."; return }
}

# change + test each one
Add-Type -AssemblyName System.DirectoryServices.AccountManagement
$ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext([System.DirectoryServices.AccountManagement.ContextType]$(if ($isDC) { "Domain" } else { "Machine" }))

foreach ($t in $targets) {
    $pw = New-Pw $t.Name
    try {
        $sec = ConvertTo-SecureString $pw -AsPlainText -Force
        if ($isDC) { Set-ADAccountPassword $t.Name -Reset -NewPassword $sec } else { Set-LocalUser $t.Name -Password $sec }

        # changed - always show it, then try a test logon
        $status = "SET (test logon failed, check by hand)"; $color = "Yellow"
        try { if ($ctx.ValidateCredentials($t.Name, $pw)) { $status = "VERIFIED"; $color = "Green" } } catch { }
        Write-Host ("{0,-16} {1,-22} {2}" -f $t.Name, $pw, $status) -ForegroundColor $color
    }
    catch {
        Write-Host ("{0,-16} {1,-22} FAILED: {2}" -f $t.Name, "(not changed)", $_.Exception.Message) -ForegroundColor Red
    }
}
Write-Host "Write these on paper, then Clear-Host. Check Hermes." -ForegroundColor Cyan

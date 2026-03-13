# =============================================================================
# Invoke-UserOnboarding.ps1
# Adds a new user to specified SharePoint groups, M365 Groups, and Teams.
# Supports single-user (parameters) and bulk mode (CSV).
# =============================================================================
# CSV format (bulk mode):
#   UserPrincipalName, SharePointSites, SharePointGroup, M365Groups, Teams
#   jane.doe@contoso.com, "https://contoso.sharepoint.com/sites/alpha|Members;https://contoso.sharepoint.com/sites/beta|Visitors", "Project Team Alpha", "Teams Channel"
#   (SharePointSites = pipe-delimited "SiteUrl|GroupName" pairs, semicolon-separated)
#
# Usage examples:
#   # Single user
#   .\Invoke-UserOnboarding.ps1 -UserPrincipalName "jane.doe@contoso.com" `
#       -SharePointSites @("https://contoso.sharepoint.com/sites/alpha|Members") `
#       -M365Groups @("All Staff") -Teams @("Project Alpha")
#
#   # Bulk from CSV
#   .\Invoke-UserOnboarding.ps1 -CsvPath ".\new-starters.csv"
#
#   # Dry-run
#   .\Invoke-UserOnboarding.ps1 -CsvPath ".\new-starters.csv" -WhatIf
# =============================================================================

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName='Single')]
param(
    # Single-user mode
    [Parameter(Mandatory, ParameterSetName='Single')]
    [string]$UserPrincipalName,

    # Array of "SiteUrl|GroupName" strings e.g. @("https://tenant.sharepoint.com/sites/hr|Members")
    [Parameter(ParameterSetName='Single')]
    [string[]]$SharePointSites = @(),

    [Parameter(ParameterSetName='Single')]
    [string[]]$M365Groups = @(),

    [Parameter(ParameterSetName='Single')]
    [string[]]$Teams = @(),

    # Bulk mode
    [Parameter(Mandatory, ParameterSetName='Bulk')]
    [string]$CsvPath,

    [ValidateSet('Interactive','AppOnly')]
    [string]$AuthMode = 'Interactive',

    [string]$ConfigPath = (Join-Path $PSScriptRoot "../_shared/Config.ps1")
)

$ErrorActionPreference = 'Stop'
. $ConfigPath
$logFile = New-LogFilePath -ScriptName "Invoke-UserOnboarding"

Write-Log "Starting Invoke-UserOnboarding" -LogFile $logFile

# ---------------------------------------------------------------------------
# Connect
# ---------------------------------------------------------------------------
. (Join-Path $PSScriptRoot "../_shared/Connect-M365.ps1") -AuthMode $AuthMode -Tool Both -ConfigPath $ConfigPath

# ---------------------------------------------------------------------------
# Build user list
# ---------------------------------------------------------------------------
$usersToProcess = @()

if ($PSCmdlet.ParameterSetName -eq 'Bulk') {
    if (-not (Test-Path $CsvPath)) { throw "CSV not found: $CsvPath" }
    $usersToProcess = Import-Csv -Path $CsvPath
    Write-Log "Bulk mode: $($usersToProcess.Count) users from $CsvPath" -LogFile $logFile
}
else {
    $usersToProcess = @([PSCustomObject]@{
        UserPrincipalName = $UserPrincipalName
        SharePointSites   = $SharePointSites -join ';'
        M365Groups        = $M365Groups -join ';'
        Teams             = $Teams -join ';'
    })
}

# ---------------------------------------------------------------------------
# Helper: Parse "SiteUrl|GroupName" pairs
# ---------------------------------------------------------------------------
function Parse-SiteGroupPairs([string]$raw) {
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    return $raw -split ';' | ForEach-Object {
        $parts = $_ -split '\|'
        [PSCustomObject]@{ SiteUrl = $parts[0].Trim(); GroupName = if ($parts.Count -gt 1) { $parts[1].Trim() } else { 'Members' } }
    }
}

# ---------------------------------------------------------------------------
# Process each user
# ---------------------------------------------------------------------------
$auditRows = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($row in $usersToProcess) {
    $upn = $row.UserPrincipalName
    Write-Host "`nOnboarding: $upn" -ForegroundColor Cyan
    Write-Log "Processing user: $upn" -LogFile $logFile

    # Validate user exists
    try {
        $userInfo = m365 aad user get --userPrincipalName $upn --output json | ConvertFrom-Json
        Write-Host "  User validated: $($userInfo.displayName)" -ForegroundColor Gray
    }
    catch {
        Write-Log "User '$upn' not found in Entra ID — skipping." -Level WARN -LogFile $logFile
        Write-Warning "  User '$upn' not found in Entra ID — skipping."
        continue
    }

    # 1. SharePoint Groups
    $sitePairs = Parse-SiteGroupPairs $row.SharePointSites
    foreach ($pair in $sitePairs) {
        if ($PSCmdlet.ShouldProcess($pair.SiteUrl, "Add $upn to group '$($pair.GroupName)'")) {
            try {
                Add-PnPGroupMember -LoginName $upn -Group $pair.GroupName -Url $pair.SiteUrl
                Write-Host "  [SP] Added to $($pair.GroupName) @ $($pair.SiteUrl)" -ForegroundColor Green
                Write-Log "Added $upn to SP group '$($pair.GroupName)' on $($pair.SiteUrl)" -LogFile $logFile
                $auditRows.Add([PSCustomObject]@{ UPN=$upn; Action='Added'; Type='SharePoint Group'; Resource="$($pair.SiteUrl) > $($pair.GroupName)"; Status='OK' })
            }
            catch {
                Write-Log "Failed adding $upn to $($pair.GroupName) on $($pair.SiteUrl): $_" -Level ERROR -LogFile $logFile
                $auditRows.Add([PSCustomObject]@{ UPN=$upn; Action='Added'; Type='SharePoint Group'; Resource="$($pair.SiteUrl) > $($pair.GroupName)"; Status="Error: $_" })
            }
        }
    }

    # 2. M365 Groups
    $m365GroupList = $row.M365Groups -split ';' | Where-Object { $_ -ne '' }
    foreach ($groupName in $m365GroupList) {
        if ($PSCmdlet.ShouldProcess($groupName, "Add $upn to M365 Group")) {
            try {
                $groupId = (m365 aad group list --output json | ConvertFrom-Json |
                            Where-Object displayName -eq $groupName | Select-Object -First 1).id
                if (-not $groupId) { throw "Group '$groupName' not found." }
                m365 aad group member add --groupId $groupId --userIds $upn | Out-Null
                Write-Host "  [M365] Added to group '$groupName'" -ForegroundColor Green
                Write-Log "Added $upn to M365 Group '$groupName'" -LogFile $logFile
                $auditRows.Add([PSCustomObject]@{ UPN=$upn; Action='Added'; Type='M365 Group'; Resource=$groupName; Status='OK' })
            }
            catch {
                Write-Log "Failed adding $upn to M365 Group '$groupName': $_" -Level ERROR -LogFile $logFile
                $auditRows.Add([PSCustomObject]@{ UPN=$upn; Action='Added'; Type='M365 Group'; Resource=$groupName; Status="Error: $_" })
            }
        }
    }

    # 3. Teams
    $teamList = $row.Teams -split ';' | Where-Object { $_ -ne '' }
    foreach ($teamName in $teamList) {
        if ($PSCmdlet.ShouldProcess($teamName, "Add $upn to Team")) {
            try {
                $teamId = (m365 teams team list --output json | ConvertFrom-Json |
                           Where-Object displayName -eq $teamName | Select-Object -First 1).id
                if (-not $teamId) { throw "Team '$teamName' not found." }
                m365 teams team member add --teamId $teamId --userIds $upn | Out-Null
                Write-Host "  [Teams] Added to team '$teamName'" -ForegroundColor Green
                Write-Log "Added $upn to Team '$teamName'" -LogFile $logFile
                $auditRows.Add([PSCustomObject]@{ UPN=$upn; Action='Added'; Type='Microsoft Team'; Resource=$teamName; Status='OK' })
            }
            catch {
                Write-Log "Failed adding $upn to Team '$teamName': $_" -Level ERROR -LogFile $logFile
                $auditRows.Add([PSCustomObject]@{ UPN=$upn; Action='Added'; Type='Microsoft Team'; Resource=$teamName; Status="Error: $_" })
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Export audit log
# ---------------------------------------------------------------------------
$timestamp   = Get-Date -Format "yyyyMMdd_HHmmss"
$auditPath   = Join-Path $DefaultOutputPath "Onboarding_Audit_$timestamp.csv"
$auditRows   | Export-Csv -Path $auditPath -NoTypeInformation -Encoding UTF8
$ok          = ($auditRows | Where-Object Status -eq 'OK').Count
$errors      = ($auditRows | Where-Object Status -like 'Error*').Count

Write-Log "Onboarding complete. OK: $ok  Errors: $errors" -LogFile $logFile
Write-Host "`nOnboarding complete. OK: $ok  Errors: $errors" -ForegroundColor $(if ($errors) { 'Yellow' } else { 'Green' })
Write-Host "Audit log: $auditPath" -ForegroundColor Gray
Write-Host "Log: $logFile" -ForegroundColor Gray

return $auditRows

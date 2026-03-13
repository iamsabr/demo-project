# =============================================================================
# Invoke-UserOffboarding.ps1
# Removes a departing user's access from all SharePoint sites, M365 Groups,
# and Microsoft Teams. Produces a full audit trail CSV.
# =============================================================================
# Usage examples:
#   # Offboard a single user (interactive prompt to confirm)
#   .\Invoke-UserOffboarding.ps1 -UserPrincipalName "john.smith@contoso.com"
#
#   # Dry-run — show what would be removed without making changes
#   .\Invoke-UserOffboarding.ps1 -UserPrincipalName "john.smith@contoso.com" -WhatIf
#
#   # Bulk offboard from CSV (column: UserPrincipalName)
#   .\Invoke-UserOffboarding.ps1 -CsvPath ".\leavers.csv"
#
#   # Skip confirmation prompt (for scheduled/automated runs)
#   .\Invoke-UserOffboarding.ps1 -UserPrincipalName "john.smith@contoso.com" -Force
# =============================================================================

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName='Single')]
param(
    [Parameter(Mandatory, ParameterSetName='Single')]
    [string]$UserPrincipalName,

    [Parameter(Mandatory, ParameterSetName='Bulk')]
    [string]$CsvPath,

    # Skip the "are you sure?" confirmation (use in automated pipelines)
    [switch]$Force,

    [ValidateSet('Interactive','AppOnly')]
    [string]$AuthMode = 'Interactive',

    [string]$ConfigPath = (Join-Path $PSScriptRoot "../_shared/Config.ps1")
)

$ErrorActionPreference = 'Stop'
. $ConfigPath
$logFile = New-LogFilePath -ScriptName "Invoke-UserOffboarding"

Write-Log "Starting Invoke-UserOffboarding" -LogFile $logFile

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
    $usersToProcess = (Import-Csv -Path $CsvPath).UserPrincipalName
    Write-Log "Bulk mode: $($usersToProcess.Count) users from $CsvPath" -LogFile $logFile
}
else {
    $usersToProcess = @($UserPrincipalName)
}

# ---------------------------------------------------------------------------
# Process each user
# ---------------------------------------------------------------------------
$allAuditRows = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($upn in $usersToProcess) {
    Write-Host "`n=============================" -ForegroundColor Magenta
    Write-Host " Offboarding: $upn" -ForegroundColor Magenta
    Write-Host "=============================" -ForegroundColor Magenta
    Write-Log "Processing offboarding for: $upn" -LogFile $logFile

    # Confirm unless -Force or -WhatIf
    if (-not $Force -and -not $WhatIfPreference) {
        $confirm = Read-Host "Confirm removal of ALL access for '$upn'? (yes/no)"
        if ($confirm -ne 'yes') {
            Write-Log "Skipped (user cancelled): $upn" -Level WARN -LogFile $logFile
            Write-Warning "Skipped: $upn"
            continue
        }
    }

    # --- Step 1: Discover current access via Get-UserAccessReport ---
    Write-Host "Step 1/4: Discovering current access..." -ForegroundColor Cyan
    $accessRecords = & (Join-Path $PSScriptRoot "Get-UserAccessReport.ps1") `
                        -UserPrincipalName $upn `
                        -NoExport `
                        -SkipConnect `
                        -AuthMode $AuthMode `
                        -ConfigPath $ConfigPath

    Write-Host "  Found $($accessRecords.Count) access records." -ForegroundColor Gray
    Write-Log "Access records discovered: $($accessRecords.Count)" -LogFile $logFile

    $auditRows = [System.Collections.Generic.List[PSCustomObject]]::new()

    # --- Step 2: Remove SharePoint Group memberships ---
    Write-Host "Step 2/4: Removing SharePoint group memberships..." -ForegroundColor Cyan
    $spRecords = $accessRecords | Where-Object { $_.ResourceType -eq 'SharePoint Site' -and $_.ViaGroup -ne '' -and $_.Role -ne 'Site Collection Admin' }

    foreach ($record in $spRecords) {
        if ($PSCmdlet.ShouldProcess($record.ResourceUrl, "Remove $upn from group '$($record.ViaGroup)'")) {
            try {
                Remove-PnPGroupMember -LoginName $upn -Group $record.ViaGroup -Url $record.ResourceUrl
                Write-Host "  [SP] Removed from '$($record.ViaGroup)' @ $($record.ResourceName)" -ForegroundColor Green
                Write-Log "Removed $upn from SP group '$($record.ViaGroup)' on $($record.ResourceUrl)" -LogFile $logFile
                $auditRows.Add([PSCustomObject]@{ UPN=$upn; Action='Removed'; Type='SharePoint Group'; Resource="$($record.ResourceUrl) > $($record.ViaGroup)"; Status='OK'; Timestamp=(Get-Date -Format 'u') })
            }
            catch {
                Write-Log "Error removing $upn from $($record.ViaGroup) on $($record.ResourceUrl): $_" -Level ERROR -LogFile $logFile
                $auditRows.Add([PSCustomObject]@{ UPN=$upn; Action='Removed'; Type='SharePoint Group'; Resource="$($record.ResourceUrl) > $($record.ViaGroup)"; Status="Error: $_"; Timestamp=(Get-Date -Format 'u') })
            }
        }
    }

    # --- Step 3: Remove site collection admin role ---
    Write-Host "Step 3/4: Removing site collection admin roles..." -ForegroundColor Cyan
    $adminRecords = $accessRecords | Where-Object { $_.ResourceType -eq 'SharePoint Site' -and $_.Role -eq 'Site Collection Admin' }

    foreach ($record in $adminRecords) {
        if ($PSCmdlet.ShouldProcess($record.ResourceUrl, "Remove $upn as site collection admin")) {
            try {
                Remove-PnPSiteCollectionAdmin -Owners $upn -Url $record.ResourceUrl
                Write-Host "  [SP] Removed as Site Collection Admin @ $($record.ResourceName)" -ForegroundColor Green
                Write-Log "Removed $upn as Site Collection Admin on $($record.ResourceUrl)" -LogFile $logFile
                $auditRows.Add([PSCustomObject]@{ UPN=$upn; Action='Removed'; Type='Site Collection Admin'; Resource=$record.ResourceUrl; Status='OK'; Timestamp=(Get-Date -Format 'u') })
            }
            catch {
                Write-Log "Error removing site admin $upn from $($record.ResourceUrl): $_" -Level ERROR -LogFile $logFile
                $auditRows.Add([PSCustomObject]@{ UPN=$upn; Action='Removed'; Type='Site Collection Admin'; Resource=$record.ResourceUrl; Status="Error: $_"; Timestamp=(Get-Date -Format 'u') })
            }
        }
    }

    # --- Step 4: Remove M365 Group & Teams memberships via m365 CLI ---
    Write-Host "Step 4/4: Removing M365 Group and Teams memberships..." -ForegroundColor Cyan
    $m365Records = $accessRecords | Where-Object { $_.ResourceType -in @('M365 Group','Microsoft Team') }

    foreach ($record in $m365Records) {
        if ($PSCmdlet.ShouldProcess($record.ResourceName, "Remove $upn from $($record.ResourceType)")) {
            try {
                if ($record.ResourceType -eq 'M365 Group') {
                    $groupId = (m365 aad group list --output json | ConvertFrom-Json |
                                Where-Object displayName -eq $record.ResourceName | Select-Object -First 1).id
                    if ($groupId) {
                        m365 aad group member remove --groupId $groupId --userIds $upn --force | Out-Null
                    }
                }
                else {
                    $teamId = (m365 teams team list --output json | ConvertFrom-Json |
                               Where-Object displayName -eq $record.ResourceName | Select-Object -First 1).id
                    if ($teamId) {
                        m365 teams team member remove --teamId $teamId --userNames $upn --force | Out-Null
                    }
                }
                Write-Host "  [$($record.ResourceType)] Removed from '$($record.ResourceName)'" -ForegroundColor Green
                Write-Log "Removed $upn from $($record.ResourceType) '$($record.ResourceName)'" -LogFile $logFile
                $auditRows.Add([PSCustomObject]@{ UPN=$upn; Action='Removed'; Type=$record.ResourceType; Resource=$record.ResourceName; Status='OK'; Timestamp=(Get-Date -Format 'u') })
            }
            catch {
                Write-Log "Error removing $upn from $($record.ResourceName): $_" -Level ERROR -LogFile $logFile
                $auditRows.Add([PSCustomObject]@{ UPN=$upn; Action='Removed'; Type=$record.ResourceType; Resource=$record.ResourceName; Status="Error: $_"; Timestamp=(Get-Date -Format 'u') })
            }
        }
    }

    $allAuditRows.AddRange($auditRows)

    $ok     = ($auditRows | Where-Object Status -eq 'OK').Count
    $errors = ($auditRows | Where-Object Status -like 'Error*').Count
    Write-Host "  Offboarding for $upn — Removed: $ok  Errors: $errors" -ForegroundColor $(if ($errors) { 'Yellow' } else { 'Green' })
}

# ---------------------------------------------------------------------------
# Export audit trail
# ---------------------------------------------------------------------------
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$auditPath = Join-Path $DefaultOutputPath "Offboarding_Audit_$timestamp.csv"
$allAuditRows | Export-Csv -Path $auditPath -NoTypeInformation -Encoding UTF8

$totalOk     = ($allAuditRows | Where-Object Status -eq 'OK').Count
$totalErrors = ($allAuditRows | Where-Object Status -like 'Error*').Count

Write-Log "Offboarding complete. Total removed: $totalOk  Errors: $totalErrors" -LogFile $logFile
Write-Host "`nOffboarding complete. Removed: $totalOk  Errors: $totalErrors" -ForegroundColor $(if ($totalErrors) { 'Yellow' } else { 'Green' })
Write-Host "Audit trail: $auditPath" -ForegroundColor Gray
Write-Host "Log: $logFile" -ForegroundColor Gray

return $allAuditRows

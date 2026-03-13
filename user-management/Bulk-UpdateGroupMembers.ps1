# =============================================================================
# Bulk-UpdateGroupMembers.ps1
# Adds or removes multiple users from M365 Groups or SharePoint groups via CSV.
# =============================================================================
# CSV format:
#   Action, GroupType, GroupName, UserPrincipalName, [SiteUrl]
#   Add,    M365,      "All Staff", jane.doe@contoso.com,
#   Remove, M365,      "All Staff", bob.jones@contoso.com,
#   Add,    SharePoint, Members,   alice.smith@contoso.com, https://contoso.sharepoint.com/sites/hr
#   Remove, SharePoint, Visitors,  old.user@contoso.com,   https://contoso.sharepoint.com/sites/hr
#
# GroupType values: M365 | SharePoint
# Action values:    Add  | Remove
#
# Usage examples:
#   .\Bulk-UpdateGroupMembers.ps1 -CsvPath ".\group-changes.csv"
#   .\Bulk-UpdateGroupMembers.ps1 -CsvPath ".\group-changes.csv" -WhatIf
# =============================================================================

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$CsvPath,

    [ValidateSet('Interactive','AppOnly')]
    [string]$AuthMode = 'Interactive',

    [string]$ConfigPath = (Join-Path $PSScriptRoot "../_shared/Config.ps1")
)

$ErrorActionPreference = 'Stop'
. $ConfigPath
$logFile = New-LogFilePath -ScriptName "Bulk-UpdateGroupMembers"

Write-Log "Starting Bulk-UpdateGroupMembers from $CsvPath" -LogFile $logFile

if (-not (Test-Path $CsvPath)) { throw "CSV not found: $CsvPath" }

# ---------------------------------------------------------------------------
# Connect
# ---------------------------------------------------------------------------
. (Join-Path $PSScriptRoot "../_shared/Connect-M365.ps1") -AuthMode $AuthMode -Tool Both -ConfigPath $ConfigPath

# ---------------------------------------------------------------------------
# Load and validate CSV
# ---------------------------------------------------------------------------
$changes = Import-Csv -Path $CsvPath
$required = @('Action','GroupType','GroupName','UserPrincipalName')
$missing  = $required | Where-Object { $_ -notin $changes[0].PSObject.Properties.Name }

if ($missing) {
    throw "CSV is missing required columns: $($missing -join ', ')"
}

Write-Log "Loaded $($changes.Count) rows from CSV" -LogFile $logFile
Write-Host "Processing $($changes.Count) group membership changes..." -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Cache M365 Group IDs to avoid repeated API calls
# ---------------------------------------------------------------------------
$m365GroupCache = @{}

function Get-M365GroupId([string]$displayName) {
    if (-not $m365GroupCache.ContainsKey($displayName)) {
        $id = (m365 aad group list --output json | ConvertFrom-Json |
               Where-Object displayName -eq $displayName | Select-Object -First 1).id
        $m365GroupCache[$displayName] = $id
    }
    return $m365GroupCache[$displayName]
}

# ---------------------------------------------------------------------------
# Process changes
# ---------------------------------------------------------------------------
$results = foreach ($row in $changes) {
    $action    = $row.Action.Trim()
    $groupType = $row.GroupType.Trim()
    $groupName = $row.GroupName.Trim()
    $upn       = $row.UserPrincipalName.Trim()
    $siteUrl   = if ($row.PSObject.Properties['SiteUrl']) { $row.SiteUrl.Trim() } else { '' }

    $description = "$action '$upn' $($action -eq 'Add' ? 'to' : 'from') $groupType group '$groupName'"
    $status      = 'Skipped'
    $error       = ''

    if (-not ($action -in @('Add','Remove'))) {
        Write-Log "Invalid Action '$action' for $upn — skipping." -Level WARN -LogFile $logFile
        continue
    }

    if ($PSCmdlet.ShouldProcess($groupName, $description)) {
        try {
            if ($groupType -eq 'M365') {
                $groupId = Get-M365GroupId $groupName
                if (-not $groupId) { throw "M365 Group '$groupName' not found." }

                if ($action -eq 'Add') {
                    m365 aad group member add --groupId $groupId --userIds $upn | Out-Null
                }
                else {
                    m365 aad group member remove --groupId $groupId --userIds $upn --force | Out-Null
                }
                $status = $action + 'ed'
            }
            elseif ($groupType -eq 'SharePoint') {
                if (-not $siteUrl) { throw "SiteUrl is required for SharePoint group operations." }

                if ($action -eq 'Add') {
                    Add-PnPGroupMember -LoginName $upn -Group $groupName -Url $siteUrl
                }
                else {
                    Remove-PnPGroupMember -LoginName $upn -Group $groupName -Url $siteUrl
                }
                $status = $action + 'ed'
            }
            else {
                throw "Unknown GroupType '$groupType'. Use 'M365' or 'SharePoint'."
            }

            Write-Host "  [OK] $description" -ForegroundColor Green
            Write-Log "OK: $description" -LogFile $logFile
        }
        catch {
            $status = 'Error'
            $error  = $_.Exception.Message
            Write-Host "  [FAIL] $description — $error" -ForegroundColor Red
            Write-Log "FAIL: $description — $error" -Level ERROR -LogFile $logFile
        }
    }

    [PSCustomObject]@{
        Action            = $action
        GroupType         = $groupType
        GroupName         = $groupName
        UserPrincipalName = $upn
        SiteUrl           = $siteUrl
        Status            = $status
        Error             = $error
        Timestamp         = (Get-Date -Format 'u')
    }
}

# ---------------------------------------------------------------------------
# Export results
# ---------------------------------------------------------------------------
$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$resultPath = Join-Path $DefaultOutputPath "BulkGroupUpdate_$timestamp.csv"
$results | Export-Csv -Path $resultPath -NoTypeInformation -Encoding UTF8

$ok     = ($results | Where-Object Status -in @('Added','Removed')).Count
$errors = ($results | Where-Object Status -eq 'Error').Count

Write-Log "Bulk-UpdateGroupMembers complete. OK: $ok  Errors: $errors" -LogFile $logFile
Write-Host "`nComplete. OK: $ok  Errors: $errors" -ForegroundColor $(if ($errors) { 'Yellow' } else { 'Green' })
Write-Host "Results: $resultPath" -ForegroundColor Gray
Write-Host "Log: $logFile" -ForegroundColor Gray

return $results

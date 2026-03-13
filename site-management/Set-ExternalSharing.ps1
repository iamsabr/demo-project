# =============================================================================
# Set-ExternalSharing.ps1
# Configure external sharing settings at the site or tenant level.
# =============================================================================
# Sharing levels:
#   Disabled                        — No external sharing allowed
#   ExistingExternalUserSharingOnly — Only existing external users in your directory
#   ExternalUserSharingOnly         — New & existing external users (sign-in required)
#   ExternalUserAndGuestSharing     — Anyone with a link (most permissive)
#
# Usage examples:
#   # Disable external sharing for a specific site
#   .\Set-ExternalSharing.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/hr" -SharingLevel Disabled
#
#   # Set tenant default (affects new sites)
#   .\Set-ExternalSharing.ps1 -TenantLevel -SharingLevel ExistingExternalUserSharingOnly
#
#   # Bulk-update multiple sites from CSV (column: SiteUrl, SharingLevel)
#   .\Set-ExternalSharing.ps1 -CsvPath ".\sharing-policy.csv"
#
#   # Dry-run
#   .\Set-ExternalSharing.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/hr" -SharingLevel Disabled -WhatIf
# =============================================================================

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName='Site')]
param(
    [Parameter(Mandatory, ParameterSetName='Site')]
    [string]$SiteUrl,

    [Parameter(Mandatory, ParameterSetName='Tenant')]
    [switch]$TenantLevel,

    [Parameter(Mandatory, ParameterSetName='Bulk')]
    [string]$CsvPath,

    [Parameter(Mandatory, ParameterSetName='Site')]
    [Parameter(Mandatory, ParameterSetName='Tenant')]
    [ValidateSet('Disabled','ExistingExternalUserSharingOnly','ExternalUserSharingOnly','ExternalUserAndGuestSharing')]
    [string]$SharingLevel,

    [ValidateSet('Interactive','AppOnly')]
    [string]$AuthMode = 'Interactive',

    [string]$ConfigPath = (Join-Path $PSScriptRoot "../_shared/Config.ps1")
)

$ErrorActionPreference = 'Stop'
. $ConfigPath
$logFile = New-LogFilePath -ScriptName "Set-ExternalSharing"

Write-Log "Starting Set-ExternalSharing" -LogFile $logFile

# ---------------------------------------------------------------------------
# Connect
# ---------------------------------------------------------------------------
. (Join-Path $PSScriptRoot "../_shared/Connect-M365.ps1") -AuthMode $AuthMode -Tool Both -ConfigPath $ConfigPath

# ---------------------------------------------------------------------------
# Tenant-level update
# ---------------------------------------------------------------------------
if ($PSCmdlet.ParameterSetName -eq 'Tenant') {
    if ($PSCmdlet.ShouldProcess("Tenant", "Set default sharing to '$SharingLevel'")) {
        Write-Log "Setting tenant-level sharing to $SharingLevel" -LogFile $logFile
        Set-PnPTenant -SharingCapability $SharingLevel

        # Also update via m365 for confirmation
        Write-Host "Tenant sharing capability set to: $SharingLevel" -ForegroundColor Green
        Write-Log "Tenant sharing updated to $SharingLevel" -LogFile $logFile
    }
    return
}

# ---------------------------------------------------------------------------
# Build site list
# ---------------------------------------------------------------------------
$sitesToProcess = @()

if ($PSCmdlet.ParameterSetName -eq 'Bulk') {
    if (-not (Test-Path $CsvPath)) { throw "CSV not found: $CsvPath" }
    $sitesToProcess = Import-Csv -Path $CsvPath
    Write-Log "Bulk mode: $($sitesToProcess.Count) sites from $CsvPath" -LogFile $logFile
}
else {
    $sitesToProcess = @([PSCustomObject]@{ SiteUrl = $SiteUrl; SharingLevel = $SharingLevel })
}

# ---------------------------------------------------------------------------
# Process each site
# ---------------------------------------------------------------------------
$results = foreach ($site in $sitesToProcess) {
    $url   = $site.SiteUrl
    $level = $site.SharingLevel

    if (-not $level) {
        Write-Log "No SharingLevel for $url — skipping." -Level WARN -LogFile $logFile
        continue
    }

    $status = 'Skipped'
    $error  = ''

    if ($PSCmdlet.ShouldProcess($url, "Set sharing to '$level'")) {
        try {
            Set-PnPTenantSite -Identity $url -SharingCapability $level
            $status = 'Updated'
            Write-Log "Set $url sharing to $level" -LogFile $logFile
            Write-Host "  [OK] $url → $level" -ForegroundColor Green
        }
        catch {
            $status = 'Error'
            $error  = $_.Exception.Message
            Write-Log "Error on $url: $error" -Level ERROR -LogFile $logFile
            Write-Host "  [FAIL] $url — $error" -ForegroundColor Red
        }
    }

    [PSCustomObject]@{ SiteUrl = $url; SharingLevel = $level; Status = $status; Error = $error }
}

$updated = ($results | Where-Object Status -eq 'Updated').Count
$errors  = ($results | Where-Object Status -eq 'Error').Count
Write-Log "Set-ExternalSharing complete. Updated: $updated  Errors: $errors" -LogFile $logFile
Write-Host "`nComplete. Updated: $updated  Errors: $errors" -ForegroundColor $(if ($errors) { 'Yellow' } else { 'Green' })
Write-Host "Log: $logFile" -ForegroundColor Gray

return $results

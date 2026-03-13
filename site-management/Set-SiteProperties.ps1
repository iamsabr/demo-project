# =============================================================================
# Set-SiteProperties.ps1
# Updates properties on one or more SharePoint site collections.
# Supports single-site mode (parameters) and bulk mode (CSV input).
# =============================================================================
# Usage examples:
#   # Update a single site
#   .\Set-SiteProperties.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/alpha" -Title "Alpha Project" -StorageQuotaMB 5120
#
#   # Bulk update from CSV (columns: SiteUrl, Title, Description, StorageQuotaMB, SharingCapability)
#   .\Set-SiteProperties.ps1 -CsvPath ".\sites-to-update.csv"
#
#   # Dry-run
#   .\Set-SiteProperties.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/alpha" -Title "New Title" -WhatIf
# =============================================================================

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName='Single')]
param(
    # Single-site mode
    [Parameter(Mandatory, ParameterSetName='Single')]
    [string]$SiteUrl,

    [Parameter(ParameterSetName='Single')]
    [string]$Title,

    [Parameter(ParameterSetName='Single')]
    [string]$Description,

    [Parameter(ParameterSetName='Single')]
    [int]$StorageQuotaMB,

    [Parameter(ParameterSetName='Single')]
    [ValidateSet('Disabled','ExistingExternalUserSharingOnly','ExternalUserSharingOnly','ExternalUserAndGuestSharing')]
    [string]$SharingCapability,

    # Bulk mode
    [Parameter(Mandatory, ParameterSetName='Bulk')]
    [string]$CsvPath,

    [ValidateSet('Interactive','AppOnly')]
    [string]$AuthMode = 'Interactive',

    [string]$ConfigPath = (Join-Path $PSScriptRoot "../_shared/Config.ps1")
)

$ErrorActionPreference = 'Stop'
. $ConfigPath
$logFile = New-LogFilePath -ScriptName "Set-SiteProperties"

Write-Log "Starting Set-SiteProperties" -LogFile $logFile

# ---------------------------------------------------------------------------
# Connect
# ---------------------------------------------------------------------------
. (Join-Path $PSScriptRoot "../_shared/Connect-M365.ps1") -AuthMode $AuthMode -Tool PnP -ConfigPath $ConfigPath

# ---------------------------------------------------------------------------
# Build list of sites to process
# ---------------------------------------------------------------------------
$sitesToProcess = @()

if ($PSCmdlet.ParameterSetName -eq 'Bulk') {
    if (-not (Test-Path $CsvPath)) { throw "CSV file not found: $CsvPath" }
    $sitesToProcess = Import-Csv -Path $CsvPath
    Write-Log "Bulk mode: $($sitesToProcess.Count) sites loaded from $CsvPath" -LogFile $logFile
}
else {
    $sitesToProcess = @([PSCustomObject]@{
        SiteUrl          = $SiteUrl
        Title            = $Title
        Description      = $Description
        StorageQuotaMB   = $StorageQuotaMB
        SharingCapability = $SharingCapability
    })
}

# ---------------------------------------------------------------------------
# Process each site
# ---------------------------------------------------------------------------
$results = foreach ($site in $sitesToProcess) {
    $url = $site.SiteUrl
    Write-Host "Processing: $url" -ForegroundColor Cyan

    $params = @{ Identity = $url }

    if ($site.Title)             { $params['Title']            = $site.Title }
    if ($site.Description)       { $params['Description']      = $site.Description }
    if ($site.StorageQuotaMB -gt 0) { $params['StorageMaximumLevel'] = [int]$site.StorageQuotaMB }
    if ($site.SharingCapability) { $params['SharingCapability'] = $site.SharingCapability }

    $status = 'Skipped'
    $error  = ''

    if ($params.Keys.Count -gt 1) {
        if ($PSCmdlet.ShouldProcess($url, "Set-PnPTenantSite with $($params.Keys -join ', ')")) {
            try {
                Set-PnPTenantSite @params
                $status = 'Updated'
                Write-Log "Updated: $url — $($params.Keys -join ', ')" -LogFile $logFile
                Write-Host "  [OK] Updated $url" -ForegroundColor Green
            }
            catch {
                $status = 'Error'
                $error  = $_.Exception.Message
                Write-Log "Error updating $url: $error" -Level ERROR -LogFile $logFile
            }
        }
    }
    else {
        Write-Log "No properties to update for $url — skipping." -Level WARN -LogFile $logFile
    }

    [PSCustomObject]@{
        SiteUrl = $url
        Status  = $status
        Error   = $error
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
$updated = ($results | Where-Object Status -eq 'Updated').Count
$errors  = ($results | Where-Object Status -eq 'Error').Count
Write-Log "Set-SiteProperties complete. Updated: $updated, Errors: $errors" -LogFile $logFile
Write-Host "`nComplete. Updated: $updated  Errors: $errors" -ForegroundColor $(if ($errors) { 'Yellow' } else { 'Green' })
Write-Host "Log: $logFile" -ForegroundColor Gray

return $results

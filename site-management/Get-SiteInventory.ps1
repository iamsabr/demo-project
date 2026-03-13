# =============================================================================
# Get-SiteInventory.ps1
# Exports a full inventory of all SharePoint site collections to CSV.
# Uses PnP.PowerShell for SharePoint details and m365 CLI for activity data.
# =============================================================================
# Usage examples:
#   # Export all sites to default output path
#   .\Get-SiteInventory.ps1
#
#   # Export with custom output file
#   .\Get-SiteInventory.ps1 -OutputPath "C:\Reports\sites.csv"
#
#   # Include personal OneDrive sites
#   .\Get-SiteInventory.ps1 -IncludePersonalSites
# =============================================================================

[CmdletBinding()]
param(
    [string]$OutputPath,

    [switch]$IncludePersonalSites,

    [ValidateSet('Interactive','AppOnly')]
    [string]$AuthMode = 'Interactive',

    [string]$ConfigPath = (Join-Path $PSScriptRoot "../_shared/Config.ps1")
)

$ErrorActionPreference = 'Stop'
. $ConfigPath
$logFile   = New-LogFilePath -ScriptName "Get-SiteInventory"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

if (-not $OutputPath) {
    $OutputPath = Join-Path $DefaultOutputPath "SiteInventory_$timestamp.csv"
}

Write-Log "Starting Get-SiteInventory — Output: $OutputPath" -LogFile $logFile

# ---------------------------------------------------------------------------
# Connect
# ---------------------------------------------------------------------------
. (Join-Path $PSScriptRoot "../_shared/Connect-M365.ps1") -AuthMode $AuthMode -Tool Both -ConfigPath $ConfigPath

# ---------------------------------------------------------------------------
# Retrieve all site collections via PnP
# ---------------------------------------------------------------------------
Write-Host "Retrieving site collections from SharePoint..." -ForegroundColor Cyan

$pnpParams = @{ IncludeOneDriveSites = $IncludePersonalSites.IsPresent }
$sites = Get-PnPTenantSite @pnpParams

Write-Host "  Found $($sites.Count) site collections." -ForegroundColor Gray

# ---------------------------------------------------------------------------
# Retrieve activity data via m365 CLI (last 30 days)
# Returns JSON array; key: SiteUrl -> LastActivityDate, FileCount
# ---------------------------------------------------------------------------
Write-Host "Retrieving site activity data via m365 CLI..." -ForegroundColor Cyan
$activityMap = @{}

try {
    $activityJson = m365 spo report activityfilecounts --period D30 --output json 2>$null
    if ($activityJson) {
        $activityData = $activityJson | ConvertFrom-Json
        foreach ($row in $activityData) {
            $activityMap[$row.'Site URL'] = $row
        }
    }
}
catch {
    Write-Log "Could not retrieve activity data: $_" -Level WARN -LogFile $logFile
}

# ---------------------------------------------------------------------------
# Build inventory rows
# ---------------------------------------------------------------------------
Write-Host "Building inventory report..." -ForegroundColor Cyan
$inventory = foreach ($site in $sites) {
    $activity = $activityMap[$site.Url]

    [PSCustomObject]@{
        Url                = $site.Url
        Title              = $site.Title
        Template           = $site.Template
        Owner              = $site.Owner
        StorageUsedMB      = [math]::Round($site.StorageUsageCurrent, 2)
        StorageQuotaMB     = $site.StorageMaximumLevel
        StorageWarningMB   = $site.StorageWarningLevel
        SharingCapability  = $site.SharingCapability
        IsHubSite          = $site.IsHubSite
        HubSiteId          = $site.HubSiteId
        LastActivityDate   = if ($activity) { $activity.'Report Date' } else { 'N/A' }
        LockState          = $site.LockState
        Status             = $site.Status
        CreatedDate        = $site.LastContentModifiedDate   # closest available proxy
    }
}

# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------
$inventory | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
Write-Log "Exported $($inventory.Count) sites to $OutputPath" -LogFile $logFile
Write-Host "Inventory saved to: $OutputPath" -ForegroundColor Green
Write-Host "Log: $logFile" -ForegroundColor Gray

# Return object for pipeline use
return $inventory

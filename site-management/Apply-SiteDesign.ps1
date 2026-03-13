# =============================================================================
# Apply-SiteDesign.ps1
# Applies a SharePoint site design to an existing site collection.
# =============================================================================
# Usage examples:
#   # Apply by design name
#   .\Apply-SiteDesign.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/alpha" -SiteDesignName "Project Template"
#
#   # Apply by design ID (GUID)
#   .\Apply-SiteDesign.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/alpha" -SiteDesignId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
#
#   # List all available site designs
#   .\Apply-SiteDesign.ps1 -ListDesigns
# =============================================================================

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName='ByName')]
param(
    [Parameter(Mandatory, ParameterSetName='ByName')]
    [Parameter(Mandatory, ParameterSetName='ById')]
    [string]$SiteUrl,

    [Parameter(Mandatory, ParameterSetName='ByName')]
    [string]$SiteDesignName,

    [Parameter(Mandatory, ParameterSetName='ById')]
    [string]$SiteDesignId,

    [Parameter(ParameterSetName='List')]
    [switch]$ListDesigns,

    # Internal switch used when called from New-SharePointSite.ps1 (already connected)
    [switch]$SkipConnect,

    [ValidateSet('Interactive','AppOnly')]
    [string]$AuthMode = 'Interactive',

    [string]$ConfigPath = (Join-Path $PSScriptRoot "../_shared/Config.ps1")
)

$ErrorActionPreference = 'Stop'
. $ConfigPath
$logFile = New-LogFilePath -ScriptName "Apply-SiteDesign"

Write-Log "Starting Apply-SiteDesign" -LogFile $logFile

# ---------------------------------------------------------------------------
# Connect (unless called from a parent script that already connected)
# ---------------------------------------------------------------------------
if (-not $SkipConnect) {
    . (Join-Path $PSScriptRoot "../_shared/Connect-M365.ps1") -AuthMode $AuthMode -Tool PnP -ConfigPath $ConfigPath
}

# ---------------------------------------------------------------------------
# List mode: show available designs
# ---------------------------------------------------------------------------
if ($ListDesigns) {
    Write-Host "`nAvailable Site Designs:" -ForegroundColor Cyan
    $designs = Get-PnPSiteDesign
    $designs | Select-Object Title, Id, WebTemplate, IsDefault, Version |
               Format-Table -AutoSize
    return $designs
}

# ---------------------------------------------------------------------------
# Resolve design ID by name if needed
# ---------------------------------------------------------------------------
$resolvedId = $SiteDesignId

if ($PSCmdlet.ParameterSetName -eq 'ByName') {
    Write-Log "Resolving site design ID for '$SiteDesignName'..." -LogFile $logFile
    $design = Get-PnPSiteDesign | Where-Object Title -eq $SiteDesignName | Select-Object -First 1

    if (-not $design) {
        throw "Site design '$SiteDesignName' not found. Run -ListDesigns to see available designs."
    }

    $resolvedId = $design.Id
    Write-Log "Resolved '$SiteDesignName' to ID $resolvedId" -LogFile $logFile
}

# ---------------------------------------------------------------------------
# Apply design
# ---------------------------------------------------------------------------
if ($PSCmdlet.ShouldProcess($SiteUrl, "Apply site design ID $resolvedId")) {
    Write-Host "Applying site design to $SiteUrl..." -ForegroundColor Cyan
    $result = Invoke-PnPSiteDesign -Identity $resolvedId -WebUrl $SiteUrl

    Write-Log "Site design applied. Outcome: $($result.Outcome)" -LogFile $logFile
    Write-Host "  [OK] Site design applied. Outcome: $($result.Outcome)" -ForegroundColor Green

    if ($result.ActionOutcome) {
        $result.ActionOutcome | ForEach-Object {
            Write-Verbose "  Action: $($_.Title) — $($_.Outcome)"
        }
    }

    Write-Host "Log: $logFile" -ForegroundColor Gray
    return $result
}

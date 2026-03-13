# =============================================================================
# New-SharePointSite.ps1
# Provisions a new SharePoint Online team site or communication site.
# =============================================================================
# Usage examples:
#   # Create a Team Site (Microsoft 365 Group-connected)
#   .\New-SharePointSite.ps1 -SiteType TeamSite -Title "Project Alpha" -Alias "projectalpha" -Owner "admin@contoso.com"
#
#   # Create a Communication Site
#   .\New-SharePointSite.ps1 -SiteType CommunicationSite -Title "Company News" -Url "https://contoso.sharepoint.com/sites/news" -Owner "admin@contoso.com"
#
#   # Dry-run (no changes made)
#   .\New-SharePointSite.ps1 -SiteType TeamSite -Title "Test Site" -Alias "testsite" -Owner "admin@contoso.com" -WhatIf
# =============================================================================

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('TeamSite','CommunicationSite')]
    [string]$SiteType,

    [Parameter(Mandatory)]
    [string]$Title,

    # TeamSite: short alias (becomes the M365 Group alias and URL fragment)
    [Parameter(ParameterSetName='TeamSite')]
    [string]$Alias,

    # CommunicationSite: full site URL
    [Parameter(ParameterSetName='CommunicationSite')]
    [string]$Url,

    [Parameter(Mandatory)]
    [string]$Owner,

    [string]$Description = "",
    [string]$TimeZone = "UTC",

    # Optional: apply a site design after creation (by name or ID)
    [string]$SiteDesignName,

    [ValidateSet('Interactive','AppOnly')]
    [string]$AuthMode = 'Interactive',

    [string]$ConfigPath = (Join-Path $PSScriptRoot "../_shared/Config.ps1")
)

$ErrorActionPreference = 'Stop'
. $ConfigPath
$logFile = New-LogFilePath -ScriptName "New-SharePointSite"

Write-Log "Starting New-SharePointSite — Type: $SiteType, Title: '$Title'" -LogFile $logFile

# ---------------------------------------------------------------------------
# Connect
# ---------------------------------------------------------------------------
. (Join-Path $PSScriptRoot "../_shared/Connect-M365.ps1") -AuthMode $AuthMode -Tool PnP -ConfigPath $ConfigPath

# ---------------------------------------------------------------------------
# Provision site
# ---------------------------------------------------------------------------
$newSiteUrl = $null

if ($SiteType -eq 'TeamSite') {
    if (-not $Alias) { throw "-Alias is required for TeamSite." }

    if ($PSCmdlet.ShouldProcess("$TenantUrl/sites/$Alias", "Create Team Site '$Title'")) {
        Write-Log "Creating TeamSite with alias '$Alias'..." -LogFile $logFile
        $newSiteUrl = New-PnPSite -Type TeamSite `
                                  -Title $Title `
                                  -Alias $Alias `
                                  -Description $Description `
                                  -Owner $Owner `
                                  -TimeZone $TimeZone
        Write-Log "TeamSite created: $newSiteUrl" -LogFile $logFile
        Write-Host "Site created: $newSiteUrl" -ForegroundColor Green
    }
}
else {
    # CommunicationSite
    if (-not $Url) { throw "-Url is required for CommunicationSite." }

    if ($PSCmdlet.ShouldProcess($Url, "Create Communication Site '$Title'")) {
        Write-Log "Creating CommunicationSite at '$Url'..." -LogFile $logFile
        $newSiteUrl = New-PnPSite -Type CommunicationSite `
                                  -Title $Title `
                                  -Url $Url `
                                  -Description $Description `
                                  -Owner $Owner `
                                  -TimeZone $TimeZone
        Write-Log "CommunicationSite created: $newSiteUrl" -LogFile $logFile
        Write-Host "Site created: $newSiteUrl" -ForegroundColor Green
    }
}

# ---------------------------------------------------------------------------
# Optionally apply a site design
# ---------------------------------------------------------------------------
if ($SiteDesignName -and $newSiteUrl -and $PSCmdlet.ShouldProcess($newSiteUrl, "Apply site design '$SiteDesignName'")) {
    Write-Log "Applying site design '$SiteDesignName' to $newSiteUrl..." -LogFile $logFile
    & (Join-Path $PSScriptRoot "Apply-SiteDesign.ps1") `
        -SiteUrl $newSiteUrl `
        -SiteDesignName $SiteDesignName `
        -AuthMode $AuthMode `
        -ConfigPath $ConfigPath `
        -SkipConnect
}

Write-Log "New-SharePointSite completed." -LogFile $logFile
Write-Host "Log: $logFile" -ForegroundColor Gray

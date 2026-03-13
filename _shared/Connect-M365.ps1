# =============================================================================
# Connect-M365.ps1
# Unified authentication helper for PnP.PowerShell and/or m365 CLI.
# Supports both Interactive (MFA) and App-Only (service principal) auth modes.
# =============================================================================
# Usage examples:
#   # Interactive login for both tools (prompts browser MFA)
#   . ".\_shared\Connect-M365.ps1" -AuthMode Interactive -Tool Both
#
#   # App-only for PnP only (scheduled automation)
#   . ".\_shared\Connect-M365.ps1" -AuthMode AppOnly -Tool PnP
#
#   # App-only for both tools using cert thumbprint from Config.ps1
#   . ".\_shared\Connect-M365.ps1" -AuthMode AppOnly -Tool Both
# =============================================================================

[CmdletBinding()]
param(
    [ValidateSet('Interactive','AppOnly')]
    [string]$AuthMode = 'Interactive',

    [ValidateSet('PnP','M365CLI','Both')]
    [string]$Tool = 'Both',

    [string]$ConfigPath = (Join-Path $PSScriptRoot "Config.ps1"),

    # Override site URL (defaults to $TenantUrl from Config.ps1)
    [string]$SiteUrl
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Load config
# ---------------------------------------------------------------------------
if (-not (Test-Path $ConfigPath)) {
    throw "Config file not found at '$ConfigPath'. Ensure Config.ps1 exists and is configured."
}
. $ConfigPath

$connectUrl = if ($SiteUrl) { $SiteUrl } else { $AdminUrl }

# ---------------------------------------------------------------------------
# Helper: Connect PnP.PowerShell
# ---------------------------------------------------------------------------
function Connect-PnP {
    Write-Host "Connecting PnP.PowerShell to $connectUrl ($AuthMode)..." -ForegroundColor Cyan

    if ($AuthMode -eq 'Interactive') {
        Connect-PnPOnline -Url $connectUrl -Interactive
    }
    else {
        # App-only: prefer thumbprint, fall back to certificate file
        if ($CertThumbprint) {
            Connect-PnPOnline -Url $connectUrl `
                              -ClientId $AppId `
                              -Thumbprint $CertThumbprint `
                              -Tenant $TenantId
        }
        elseif ($CertPath) {
            $secPwd = if ($CertPassword) {
                ConvertTo-SecureString $CertPassword -AsPlainText -Force
            } else { $null }

            Connect-PnPOnline -Url $connectUrl `
                              -ClientId $AppId `
                              -CertificatePath $CertPath `
                              -CertificatePassword $secPwd `
                              -Tenant $TenantId
        }
        else {
            throw "AppOnly auth requires either CertThumbprint or CertPath in Config.ps1 (or env vars)."
        }
    }

    Write-Host "  [OK] PnP.PowerShell connected" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Helper: Connect m365 CLI
# ---------------------------------------------------------------------------
function Connect-M365CLI {
    Write-Host "Connecting m365 CLI ($AuthMode)..." -ForegroundColor Cyan

    # Check m365 is available
    if (-not (Get-Command m365 -ErrorAction SilentlyContinue)) {
        throw "m365 CLI not found. Run _shared\Install-RequiredModules.ps1 first."
    }

    if ($AuthMode -eq 'Interactive') {
        m365 login --authType browser
    }
    else {
        if ($CertPath) {
            m365 login --authType certificate `
                       --appId $AppId `
                       --tenant $TenantId `
                       --certificateFile $CertPath `
                       --password $CertPassword
        }
        elseif ($CertThumbprint) {
            # m365 CLI can use thumbprint if cert is in Windows certificate store
            m365 login --authType certificate `
                       --appId $AppId `
                       --tenant $TenantId `
                       --thumbprint $CertThumbprint
        }
        else {
            throw "AppOnly auth requires CertPath or CertThumbprint in Config.ps1."
        }
    }

    Write-Host "  [OK] m365 CLI connected" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Connect requested tools
# ---------------------------------------------------------------------------
switch ($Tool) {
    'PnP'    { Connect-PnP }
    'M365CLI'{ Connect-M365CLI }
    'Both'   { Connect-PnP; Connect-M365CLI }
}

Write-Host "Authentication complete. Ready to run scripts.`n" -ForegroundColor Green

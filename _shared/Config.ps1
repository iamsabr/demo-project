# =============================================================================
# Config.ps1 — Central configuration for M365 SharePoint & Teams automation
# =============================================================================
# Dot-source this file at the top of every script:
#   . "$PSScriptRoot/../_shared/Config.ps1"
#
# IMPORTANT: Do not commit real credentials. Use environment variables or
# a secrets manager (e.g. Azure Key Vault) for production secrets.
# =============================================================================

# ---------------------------------------------------------------------------
# Tenant Identity
# ---------------------------------------------------------------------------
$TenantId   = $env:M365_TENANT_ID   ?? "YOUR-TENANT-ID-GUID"
$TenantUrl  = $env:M365_TENANT_URL  ?? "https://yourtenant.sharepoint.com"
$AdminUrl   = $env:M365_ADMIN_URL   ?? "https://yourtenant-admin.sharepoint.com"

# ---------------------------------------------------------------------------
# App-Only Authentication (Azure AD App Registration)
# Populate these for unattended / scheduled automation.
# ---------------------------------------------------------------------------
$AppId           = $env:M365_APP_ID           ?? "YOUR-APP-ID-GUID"
$CertThumbprint  = $env:M365_CERT_THUMBPRINT  ?? "YOUR-CERT-THUMBPRINT"
$CertPath        = $env:M365_CERT_PATH        ?? ""   # Path to .pfx file (alternative to thumbprint)
$CertPassword    = $env:M365_CERT_PASSWORD    ?? ""   # Password for .pfx file

# ---------------------------------------------------------------------------
# Output & Logging
# ---------------------------------------------------------------------------
$LogPath           = $env:M365_LOG_PATH ?? (Join-Path $PSScriptRoot "../logs")
$DefaultOutputPath = $env:M365_OUTPUT_PATH ?? (Join-Path $PSScriptRoot "../output")

# Ensure output directories exist
foreach ($dir in @($LogPath, $DefaultOutputPath)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# ---------------------------------------------------------------------------
# Helper: Write timestamped log entry
# ---------------------------------------------------------------------------
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')] [string]$Level = 'INFO',
        [string]$LogFile
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"

    Write-Verbose $entry

    if ($Level -eq 'ERROR') { Write-Error $Message }
    elseif ($Level -eq 'WARN') { Write-Warning $Message }

    if ($LogFile) {
        $entry | Out-File -FilePath $LogFile -Append -Encoding UTF8
    }
}

# ---------------------------------------------------------------------------
# Helper: Generate a timestamped log file path for a given script name
# ---------------------------------------------------------------------------
function New-LogFilePath {
    param([Parameter(Mandatory)] [string]$ScriptName)
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    return Join-Path $LogPath "${ScriptName}_${timestamp}.log"
}

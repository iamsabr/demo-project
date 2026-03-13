# =============================================================================
# Install-RequiredModules.ps1
# Ensures all required PowerShell modules and CLI tools are installed.
# Run once per machine / automation environment to bootstrap dependencies.
# =============================================================================
# Usage:
#   .\Install-RequiredModules.ps1
#   .\Install-RequiredModules.ps1 -Scope CurrentUser   # No admin rights needed
# =============================================================================

[CmdletBinding()]
param(
    [ValidateSet('CurrentUser','AllUsers')]
    [string]$Scope = 'CurrentUser',

    [switch]$SkipM365CLI,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# PowerShell Modules
# ---------------------------------------------------------------------------
$requiredModules = @(
    @{ Name = 'PnP.PowerShell';                MinVersion = '2.0.0' },
    @{ Name = 'MicrosoftTeams';                MinVersion = '6.0.0' },
    @{ Name = 'Microsoft.Graph';               MinVersion = '2.0.0' },
    @{ Name = 'ExchangeOnlineManagement';      MinVersion = '3.0.0' }
)

Write-Host "`n=== Checking PowerShell Modules ===" -ForegroundColor Cyan

# Ensure PowerShellGet is up to date
Write-Host "Updating PowerShellGet..." -ForegroundColor Gray
Install-Module -Name PowerShellGet -Scope $Scope -Force -AllowClobber -ErrorAction SilentlyContinue

foreach ($mod in $requiredModules) {
    $installed = Get-Module -ListAvailable -Name $mod.Name |
                    Sort-Object Version -Descending |
                    Select-Object -First 1

    if ($installed -and ([version]$installed.Version -ge [version]$mod.MinVersion) -and -not $Force) {
        Write-Host "  [OK] $($mod.Name) v$($installed.Version)" -ForegroundColor Green
    }
    else {
        $action = if ($installed) { "Updating" } else { "Installing" }
        Write-Host "  [$action] $($mod.Name) (requires >= $($mod.MinVersion))..." -ForegroundColor Yellow
        try {
            Install-Module -Name $mod.Name -Scope $Scope -MinimumVersion $mod.MinVersion `
                           -Force:$Force -AllowClobber -Repository PSGallery
            $ver = (Get-Module -ListAvailable -Name $mod.Name | Sort-Object Version -Descending | Select-Object -First 1).Version
            Write-Host "  [OK] $($mod.Name) v$ver installed" -ForegroundColor Green
        }
        catch {
            Write-Warning "  [FAIL] Could not install $($mod.Name): $_"
        }
    }
}

# ---------------------------------------------------------------------------
# Microsoft 365 CLI (m365)
# ---------------------------------------------------------------------------
if (-not $SkipM365CLI) {
    Write-Host "`n=== Checking Microsoft 365 CLI (m365) ===" -ForegroundColor Cyan

    $m365Installed = $null -ne (Get-Command m365 -ErrorAction SilentlyContinue)

    if ($m365Installed -and -not $Force) {
        $ver = (m365 --version 2>&1)
        Write-Host "  [OK] m365 CLI $ver" -ForegroundColor Green
    }
    else {
        # Check for Node.js / npm
        $npmAvailable = $null -ne (Get-Command npm -ErrorAction SilentlyContinue)

        if ($npmAvailable) {
            $action = if ($m365Installed) { "Updating" } else { "Installing" }
            Write-Host "  [$action] m365 CLI via npm..." -ForegroundColor Yellow
            try {
                npm install -g @pnp/cli-microsoft365 2>&1 | Write-Verbose
                $ver = (m365 --version 2>&1)
                Write-Host "  [OK] m365 CLI $ver installed" -ForegroundColor Green
            }
            catch {
                Write-Warning "  [FAIL] npm install failed: $_"
            }
        }
        else {
            Write-Warning "  [SKIP] npm not found. Install Node.js from https://nodejs.org, then re-run."
            Write-Host "  Alternatively, install m365 CLI via winget:" -ForegroundColor Gray
            Write-Host "    winget install --id=Microsoft.365CLI" -ForegroundColor Gray
        }
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host "`n=== Module Installation Complete ===" -ForegroundColor Cyan
Write-Host "Next step: Edit _shared/Config.ps1 with your tenant details, then run:" -ForegroundColor Gray
Write-Host "  .\_shared\Connect-M365.ps1 -AuthMode Interactive" -ForegroundColor Gray

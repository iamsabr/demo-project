# =============================================================================
# Get-UserAccessReport.ps1
# Generates a report of every SharePoint site, M365 Group, and Team that a
# user has access to. Used standalone or called by offboarding scripts.
# =============================================================================
# Usage examples:
#   # Report for a single user
#   .\Get-UserAccessReport.ps1 -UserPrincipalName "john.smith@contoso.com"
#
#   # Custom output path
#   .\Get-UserAccessReport.ps1 -UserPrincipalName "john.smith@contoso.com" -OutputPath "C:\Reports\john-access.csv"
#
#   # Return results as objects (for pipeline/script use) without saving file
#   $access = .\Get-UserAccessReport.ps1 -UserPrincipalName "john.smith@contoso.com" -NoExport
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$UserPrincipalName,

    [string]$OutputPath,

    [switch]$NoExport,

    # Internal switch: skip connect when called from offboarding script
    [switch]$SkipConnect,

    [ValidateSet('Interactive','AppOnly')]
    [string]$AuthMode = 'Interactive',

    [string]$ConfigPath = (Join-Path $PSScriptRoot "../_shared/Config.ps1")
)

$ErrorActionPreference = 'Stop'
. $ConfigPath
$logFile   = New-LogFilePath -ScriptName "Get-UserAccessReport"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

if (-not $OutputPath -and -not $NoExport) {
    $safeName   = $UserPrincipalName -replace '[^a-zA-Z0-9]', '-'
    $OutputPath = Join-Path $DefaultOutputPath "UserAccess_${safeName}_${timestamp}.csv"
}

Write-Log "Starting Get-UserAccessReport for $UserPrincipalName" -LogFile $logFile

# ---------------------------------------------------------------------------
# Connect
# ---------------------------------------------------------------------------
if (-not $SkipConnect) {
    . (Join-Path $PSScriptRoot "../_shared/Connect-M365.ps1") -AuthMode $AuthMode -Tool Both -ConfigPath $ConfigPath
}

# ---------------------------------------------------------------------------
# Validate user exists
# ---------------------------------------------------------------------------
Write-Host "Validating user '$UserPrincipalName'..." -ForegroundColor Cyan
try {
    $userJson = m365 aad user get --userPrincipalName $UserPrincipalName --output json 2>&1
    $user     = $userJson | ConvertFrom-Json
    Write-Host "  Found: $($user.displayName) ($($user.userPrincipalName))" -ForegroundColor Green
}
catch {
    throw "User '$UserPrincipalName' not found in Entra ID: $_"
}

$accessRecords = [System.Collections.Generic.List[PSCustomObject]]::new()

# ---------------------------------------------------------------------------
# 1. Check SharePoint site membership
# ---------------------------------------------------------------------------
Write-Host "Scanning SharePoint sites..." -ForegroundColor Cyan
$allSites = Get-PnPTenantSite | Where-Object Template -NotLike 'SPSPERS*'

foreach ($site in $allSites) {
    try {
        # Check if user is a site collection admin
        $admins = Get-PnPSiteCollectionAdmin -Url $site.Url -ErrorAction SilentlyContinue
        if ($admins | Where-Object LoginName -like "*$UserPrincipalName*") {
            $accessRecords.Add([PSCustomObject]@{
                ResourceType = 'SharePoint Site'
                ResourceName = $site.Title
                ResourceUrl  = $site.Url
                Role         = 'Site Collection Admin'
                ViaGroup     = ''
            })
        }

        # Check group membership within the site
        $groups = Get-PnPGroup -Url $site.Url -ErrorAction SilentlyContinue
        foreach ($group in $groups) {
            $members = Get-PnPGroupMember -Group $group -ErrorAction SilentlyContinue
            if ($members | Where-Object LoginName -like "*$UserPrincipalName*") {
                $accessRecords.Add([PSCustomObject]@{
                    ResourceType = 'SharePoint Site'
                    ResourceName = $site.Title
                    ResourceUrl  = $site.Url
                    Role         = $group.Title
                    ViaGroup     = $group.Title
                })
            }
        }
    }
    catch {
        Write-Log "Could not inspect site $($site.Url): $_" -Level WARN -LogFile $logFile
    }
}

Write-Host "  SharePoint scan complete. $($accessRecords.Count) records so far." -ForegroundColor Gray

# ---------------------------------------------------------------------------
# 2. Check M365 Group membership via m365 CLI
# ---------------------------------------------------------------------------
Write-Host "Scanning M365 Groups..." -ForegroundColor Cyan
try {
    $groupsJson = m365 aad user memberof --userId $UserPrincipalName --output json 2>&1
    $m365Groups  = $groupsJson | ConvertFrom-Json

    foreach ($grp in $m365Groups) {
        $accessRecords.Add([PSCustomObject]@{
            ResourceType = 'M365 Group'
            ResourceName = $grp.displayName
            ResourceUrl  = "https://admin.microsoft.com"
            Role         = 'Member'
            ViaGroup     = $grp.displayName
        })
    }
    Write-Host "  Found $($m365Groups.Count) M365 Group memberships." -ForegroundColor Gray
}
catch {
    Write-Log "Could not retrieve M365 Groups: $_" -Level WARN -LogFile $logFile
}

# ---------------------------------------------------------------------------
# 3. Check Teams membership via m365 CLI
# ---------------------------------------------------------------------------
Write-Host "Scanning Microsoft Teams..." -ForegroundColor Cyan
try {
    $teamsJson = m365 teams team list --userId $UserPrincipalName --output json 2>&1
    $teams      = $teamsJson | ConvertFrom-Json

    foreach ($team in $teams) {
        # Determine if owner or member
        $roleJson    = m365 teams team member list --teamId $team.id --output json 2>&1
        $teamMembers = $roleJson | ConvertFrom-Json
        $thisUser    = $teamMembers | Where-Object { $_.email -eq $UserPrincipalName -or $_.userPrincipalName -eq $UserPrincipalName }

        $accessRecords.Add([PSCustomObject]@{
            ResourceType = 'Microsoft Team'
            ResourceName = $team.displayName
            ResourceUrl  = "https://teams.microsoft.com"
            Role         = if ($thisUser.roles -contains 'owner') { 'Owner' } else { 'Member' }
            ViaGroup     = ''
        })
    }
    Write-Host "  Found $($teams.Count) Team memberships." -ForegroundColor Gray
}
catch {
    Write-Log "Could not retrieve Teams: $_" -Level WARN -LogFile $logFile
}

# ---------------------------------------------------------------------------
# Export & summary
# ---------------------------------------------------------------------------
Write-Log "Total access records found: $($accessRecords.Count)" -LogFile $logFile
Write-Host "`nTotal access records: $($accessRecords.Count)" -ForegroundColor Cyan

if (-not $NoExport) {
    $accessRecords | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Host "Report saved to: $OutputPath" -ForegroundColor Green
}

Write-Host "Log: $logFile" -ForegroundColor Gray
return $accessRecords

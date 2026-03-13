# Usage Examples

Quick-reference examples for all scripts. All examples assume you are in the repo root.

---

## Bootstrap

```powershell
# Install all required modules and CLI tools
.\_shared\Install-RequiredModules.ps1

# Connect interactively (browser MFA) — both PnP and m365
.\_shared\Connect-M365.ps1 -AuthMode Interactive -Tool Both

# Connect app-only (cert) — both tools
.\_shared\Connect-M365.ps1 -AuthMode AppOnly -Tool Both
```

---

## Site Management

### Provision a new site

```powershell
# Team Site (M365 Group-connected)
.\site-management\New-SharePointSite.ps1 `
    -SiteType TeamSite `
    -Title "Project Alpha" `
    -Alias "projectalpha" `
    -Owner "admin@contoso.com"

# Communication Site
.\site-management\New-SharePointSite.ps1 `
    -SiteType CommunicationSite `
    -Title "Company News" `
    -Url "https://contoso.sharepoint.com/sites/news" `
    -Owner "admin@contoso.com"

# Provision and immediately apply a site design
.\site-management\New-SharePointSite.ps1 `
    -SiteType TeamSite -Title "HR Portal" -Alias "hrportal" `
    -Owner "hr.admin@contoso.com" -SiteDesignName "HR Template"

# Dry-run — preview without making changes
.\site-management\New-SharePointSite.ps1 `
    -SiteType TeamSite -Title "Test" -Alias "test123" `
    -Owner "admin@contoso.com" -WhatIf
```

### Get full site inventory

```powershell
# Export all sites to ./output/
.\site-management\Get-SiteInventory.ps1

# Custom output path
.\site-management\Get-SiteInventory.ps1 -OutputPath "C:\Reports\sites.csv"

# Include OneDrive/personal sites
.\site-management\Get-SiteInventory.ps1 -IncludePersonalSites
```

### Update site properties

```powershell
# Single site
.\site-management\Set-SiteProperties.ps1 `
    -SiteUrl "https://contoso.sharepoint.com/sites/alpha" `
    -Title "Alpha Project (2025)" `
    -StorageQuotaMB 10240

# Bulk update — CSV columns: SiteUrl, Title, Description, StorageQuotaMB, SharingCapability
.\site-management\Set-SiteProperties.ps1 -CsvPath ".\sites-to-update.csv"

# Preview changes
.\site-management\Set-SiteProperties.ps1 `
    -SiteUrl "https://contoso.sharepoint.com/sites/alpha" -Title "New Title" -WhatIf
```

### Configure external sharing

```powershell
# Disable external sharing on a specific site
.\site-management\Set-ExternalSharing.ps1 `
    -SiteUrl "https://contoso.sharepoint.com/sites/hr" -SharingLevel Disabled

# Allow only already-known external users
.\site-management\Set-ExternalSharing.ps1 `
    -SiteUrl "https://contoso.sharepoint.com/sites/partners" `
    -SharingLevel ExistingExternalUserSharingOnly

# Set tenant-wide default
.\site-management\Set-ExternalSharing.ps1 -TenantLevel -SharingLevel ExternalUserSharingOnly

# Bulk update from CSV — columns: SiteUrl, SharingLevel
.\site-management\Set-ExternalSharing.ps1 -CsvPath ".\sharing-policy.csv"
```

### Apply a site design

```powershell
# List all available site designs
.\site-management\Apply-SiteDesign.ps1 -ListDesigns

# Apply by name
.\site-management\Apply-SiteDesign.ps1 `
    -SiteUrl "https://contoso.sharepoint.com/sites/alpha" `
    -SiteDesignName "Project Template"

# Apply by GUID
.\site-management\Apply-SiteDesign.ps1 `
    -SiteUrl "https://contoso.sharepoint.com/sites/alpha" `
    -SiteDesignId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

---

## User Management

### Onboarding

```powershell
# Single user — add to specific sites, groups, and Teams
.\user-management\Invoke-UserOnboarding.ps1 `
    -UserPrincipalName "jane.doe@contoso.com" `
    -SharePointSites @(
        "https://contoso.sharepoint.com/sites/alpha|Members",
        "https://contoso.sharepoint.com/sites/hr|Visitors"
    ) `
    -M365Groups @("All Staff","Project Alpha") `
    -Teams @("Project Alpha Team")

# Bulk onboarding from CSV
# CSV columns: UserPrincipalName, SharePointSites, M365Groups, Teams
# SharePointSites format: "SiteUrl|GroupName" pairs separated by semicolons
.\user-management\Invoke-UserOnboarding.ps1 -CsvPath ".\new-starters.csv"

# Dry-run preview
.\user-management\Invoke-UserOnboarding.ps1 -CsvPath ".\new-starters.csv" -WhatIf
```

### Offboarding

```powershell
# Offboard a single user (prompts for confirmation)
.\user-management\Invoke-UserOffboarding.ps1 -UserPrincipalName "john.smith@contoso.com"

# Dry-run — show what would be removed without making changes
.\user-management\Invoke-UserOffboarding.ps1 -UserPrincipalName "john.smith@contoso.com" -WhatIf

# Bulk offboard from CSV (column: UserPrincipalName)
.\user-management\Invoke-UserOffboarding.ps1 -CsvPath ".\leavers.csv"

# Skip confirmation prompt (for automated pipelines)
.\user-management\Invoke-UserOffboarding.ps1 `
    -UserPrincipalName "john.smith@contoso.com" -Force
```

### Access reporting

```powershell
# Full access report for a user (exports CSV to ./output/)
.\user-management\Get-UserAccessReport.ps1 -UserPrincipalName "john.smith@contoso.com"

# Custom output path
.\user-management\Get-UserAccessReport.ps1 `
    -UserPrincipalName "john.smith@contoso.com" `
    -OutputPath "C:\Reports\john-access.csv"

# Return as PowerShell objects (no file saved) — pipe or assign
$access = .\user-management\Get-UserAccessReport.ps1 `
    -UserPrincipalName "john.smith@contoso.com" -NoExport

$access | Where-Object ResourceType -eq 'Microsoft Team'
```

### Bulk group membership changes

```powershell
# Process a CSV of add/remove operations
# CSV columns: Action, GroupType, GroupName, UserPrincipalName, [SiteUrl]
.\user-management\Bulk-UpdateGroupMembers.ps1 -CsvPath ".\group-changes.csv"

# Preview first
.\user-management\Bulk-UpdateGroupMembers.ps1 -CsvPath ".\group-changes.csv" -WhatIf
```

**Example CSV (`group-changes.csv`):**

```csv
Action,GroupType,GroupName,UserPrincipalName,SiteUrl
Add,M365,All Staff,jane.new@contoso.com,
Remove,M365,Contractors,old.contractor@contoso.com,
Add,SharePoint,Members,jane.new@contoso.com,https://contoso.sharepoint.com/sites/hr
Remove,SharePoint,Visitors,old.contractor@contoso.com,https://contoso.sharepoint.com/sites/hr
```

---

## Auth Mode Reference

All scripts accept `-AuthMode Interactive` (default) or `-AuthMode AppOnly`.

```powershell
# Use app-only auth for any script
.\site-management\Get-SiteInventory.ps1 -AuthMode AppOnly

# Specify a non-default config file location
.\site-management\Get-SiteInventory.ps1 -ConfigPath "C:\config\prod-config.ps1"
```

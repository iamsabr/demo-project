# M365 SharePoint & Teams Admin Automation

A PowerShell script library for automating common Microsoft 365 SharePoint Online and Microsoft Teams administrative tasks. Uses both **PnP.PowerShell** and **Microsoft 365 CLI (`m365`)** to cover the full range of admin operations.

## Features

- **Dual-tool approach** — PnP.PowerShell for deep SharePoint integration; m365 CLI for Teams, Entra ID, and cross-service tasks
- **Flexible authentication** — Interactive (MFA) and App-Only (service principal) auth supported on every script
- **WhatIf / dry-run support** — Preview all mutating operations safely before executing
- **Timestamped logging** — Every script writes structured logs to `./logs/`
- **CSV-driven bulk operations** — Onboarding, offboarding, and group updates all support CSV input

## Quick Start

```powershell
# 1. Install dependencies
.\_shared\Install-RequiredModules.ps1

# 2. Configure tenant (edit or set environment variables — see docs/setup.md)
notepad .\_shared\Config.ps1

# 3. Test connectivity
.\_shared\Connect-M365.ps1 -AuthMode Interactive -Tool Both

# 4. Run a safe read-only report
.\site-management\Get-SiteInventory.ps1
```

## Structure

```
_shared/                    Shared bootstrap, auth, and config scripts
  Config.ps1                  Tenant settings (URL, App ID, cert, log path)
  Connect-M365.ps1            Unified auth helper (Interactive or App-Only)
  Install-RequiredModules.ps1 Module/CLI installer

site-management/            SharePoint site lifecycle automation
  New-SharePointSite.ps1      Provision team or communication sites
  Get-SiteInventory.ps1       Export all site collections to CSV
  Set-SiteProperties.ps1      Update title, quota, description (bulk-capable)
  Set-ExternalSharing.ps1     Control sharing per-site or tenant-wide
  Apply-SiteDesign.ps1        Stamp site designs onto existing sites

user-management/            User onboarding, offboarding, and access control
  Invoke-UserOnboarding.ps1   Add users to sites, groups, and Teams (bulk CSV)
  Invoke-UserOffboarding.ps1  Remove all access + produce audit trail
  Get-UserAccessReport.ps1    Find everywhere a user has access
  Bulk-UpdateGroupMembers.ps1 Add/remove users from groups via CSV

docs/
  setup.md                  Prerequisites, Azure AD app setup, troubleshooting
  usage-examples.md         Copy-paste examples for all scripts

logs/                       Auto-created — timestamped log files per script run
output/                     Auto-created — CSV reports and audit exports
```

## Authentication

All scripts accept `-AuthMode Interactive` (default) or `-AuthMode AppOnly`.

| Mode | When to use |
|---|---|
| `Interactive` | Manual/ad-hoc admin tasks. Prompts browser MFA sign-in. |
| `AppOnly` | Scheduled automation, pipelines. Uses Azure AD app + certificate. |

See [docs/setup.md](docs/setup.md) for Azure AD app registration instructions.

## Key Dependencies

| Tool | Install |
|---|---|
| PnP.PowerShell | `Install-Module PnP.PowerShell` |
| m365 CLI | `npm install -g @pnp/cli-microsoft365` |
| MicrosoftTeams | `Install-Module MicrosoftTeams` |
| Microsoft.Graph | `Install-Module Microsoft.Graph` |

Or run `.\_shared\Install-RequiredModules.ps1` to install everything at once.

## Documentation

- [Setup guide](docs/setup.md) — installation, configuration, and Azure AD setup
- [Usage examples](docs/usage-examples.md) — ready-to-run examples for every script

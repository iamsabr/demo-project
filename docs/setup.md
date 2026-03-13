# Setup Guide

## Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| PowerShell | 7.2+ | Cross-platform. [Download](https://aka.ms/powershell) |
| Node.js / npm | 18+ | Required for m365 CLI |
| Azure AD App Registration | — | Required for app-only (unattended) auth |

---

## Step 1 — Install Required Modules

Run the bootstrap installer once on each machine or automation host:

```powershell
cd <repo-root>
.\_shared\Install-RequiredModules.ps1
```

This installs:
- **PnP.PowerShell** (modern, cross-platform)
- **m365 CLI** (`@pnp/cli-microsoft365` via npm)
- **MicrosoftTeams** PowerShell module
- **Microsoft.Graph** PowerShell module

---

## Step 2 — Configure `_shared/Config.ps1`

Open `_shared/Config.ps1` and fill in your tenant details, **or** set environment variables (preferred for security):

| Setting | Environment Variable | Description |
|---|---|---|
| Tenant URL | `M365_TENANT_URL` | e.g. `https://contoso.sharepoint.com` |
| Admin URL | `M365_ADMIN_URL` | e.g. `https://contoso-admin.sharepoint.com` |
| Tenant ID | `M365_TENANT_ID` | Azure AD tenant GUID |
| App ID | `M365_APP_ID` | App registration client ID (app-only auth) |
| Cert thumbprint | `M365_CERT_THUMBPRINT` | For Windows cert store auth |
| Cert path | `M365_CERT_PATH` | Path to `.pfx` file (alternative) |
| Cert password | `M365_CERT_PASSWORD` | `.pfx` password |
| Log path | `M365_LOG_PATH` | Defaults to `./logs/` |
| Output path | `M365_OUTPUT_PATH` | Defaults to `./output/` |

**Never commit real credentials.** Use environment variables or an Azure Key Vault reference.

---

## Step 3 — Set Up Azure AD App Registration (App-Only Auth)

For unattended/scheduled automation you need an Azure AD app registration:

1. Go to **Azure Portal → Azure Active Directory → App registrations → New registration**
2. Name it (e.g. `SP-Automation-AppOnly`) and register
3. Under **API permissions**, add:
   - `Sites.FullControl.All` (SharePoint)
   - `Group.ReadWrite.All` (Microsoft Graph)
   - `Team.ReadWrite.All` (Microsoft Graph)
   - Grant admin consent
4. Under **Certificates & secrets**, upload a self-signed certificate:
   ```powershell
   # Generate a self-signed cert (Windows)
   $cert = New-SelfSignedCertificate -Subject "CN=SP-Automation" -CertStoreLocation "Cert:\CurrentUser\My" -KeyExportPolicy Exportable -NotAfter (Get-Date).AddYears(2)
   $cert.Thumbprint  # Copy this into Config.ps1 / M365_CERT_THUMBPRINT
   ```
5. Copy the **Application (client) ID** → `M365_APP_ID`
6. Copy the **Directory (tenant) ID** → `M365_TENANT_ID`

---

## Step 4 — Test Connectivity

```powershell
# Interactive MFA login (both tools)
.\_shared\Connect-M365.ps1 -AuthMode Interactive -Tool Both

# App-only login (both tools)
.\_shared\Connect-M365.ps1 -AuthMode AppOnly -Tool Both
```

---

## Step 5 — Verify with a Read-Only Script

```powershell
# Export all sites — safe, read-only
.\site-management\Get-SiteInventory.ps1
```

Check `./output/` for the resulting CSV.

---

## Folder Structure

```
_shared/          Shared utilities — always dot-sourced by other scripts
site-management/  SharePoint site lifecycle scripts
user-management/  User onboarding, offboarding, and access reporting
docs/             This documentation
logs/             Auto-created — timestamped log files
output/           Auto-created — CSV and report exports
```

---

## Common Issues

| Problem | Solution |
|---|---|
| `Connect-PnPOnline: Access denied` | Ensure your account or app has SharePoint admin rights |
| `m365: command not found` | Re-run `Install-RequiredModules.ps1`; ensure npm is in PATH |
| `AppOnly auth fails` | Check cert thumbprint matches app registration; grant admin consent |
| `Get-PnPTenantSite` returns empty | Run as a SharePoint tenant admin, not a regular user |

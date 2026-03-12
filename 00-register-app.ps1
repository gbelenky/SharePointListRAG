<#
.SYNOPSIS
    Registers an Azure AD (Entra ID) application for SharePoint List Search.

.DESCRIPTION
    Creates an App Registration with:
      - Microsoft Graph Sites.Read.All (Application) for reading SharePoint lists
      - A client secret for the .NET ingestion app
      - A redirect URI for PnP PowerShell interactive login
    Outputs the values needed for env.template / .env and PnP connection.

.PREREQUISITES
    - Azure CLI: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli
    - You must be signed in: az login
    - You need permissions to create App Registrations in your tenant
      (or Application Developer role in Entra ID)

.PARAMETER AppName
    Display name for the App Registration.

.PARAMETER SecretExpiryMonths
    How many months the client secret should be valid. Default: 12.

.EXAMPLE
    .\00-register-app.ps1
    .\00-register-app.ps1 -AppName "My FAQ Search App" -SecretExpiryMonths 6
#>

param(
    [string]$AppName = "SharePoint FAQ Search",
    [int]$SecretExpiryMonths = 12
)

$ErrorActionPreference = "Stop"

# ── Verify Azure CLI is available and signed in ──────────────
Write-Host "Checking Azure CLI login..." -ForegroundColor Cyan
try {
    $accountJson = az account show --only-show-errors --output json
    $account = $accountJson | ConvertFrom-Json
    Write-Host "Signed in as: $($account.user.name) (Tenant: $($account.tenantId))" -ForegroundColor Green
    $tenantId = $account.tenantId
} catch {
    Write-Host "ERROR: Not signed in to Azure CLI. Run 'az login' first." -ForegroundColor Red
    exit 1
}

# ── API permission IDs ─────────────────────────────────────────
# Well-known GUIDs for Microsoft Graph and SharePoint permissions.

$graphAppId = "00000003-0000-0000-c000-000000000000"  # Microsoft Graph
$sharepointAppId = "00000003-0000-0ff1-ce00-000000000000"  # SharePoint Online

# Microsoft Graph — Sites.Read.All (Application) — for .NET backend ingestion
$graphSitesReadAllAppRoleId = "332a536c-c7ef-4017-ab91-336970924f0d"

# SharePoint — AllSites.Manage (Delegated) — for PnP PowerShell interactive login
$spAllSitesManageDelegatedId = "b3f70a70-8a4b-4e95-929a-b806364c917d"

# ── Create the App Registration ──────────────────────────────
Write-Host "`nCreating App Registration: '$AppName' ..." -ForegroundColor Cyan

# Check if app already exists
$existingAppsJson = az ad app list --display-name "$AppName" --query "[].{id:id, appId:appId}" --only-show-errors --output json
$existingApps = $existingAppsJson | ConvertFrom-Json
if ($existingApps -and $existingApps.Count -gt 0) {
    Write-Host "App '$AppName' already exists (Client ID: $($existingApps[0].appId))." -ForegroundColor Yellow
    $response = Read-Host "Do you want to continue and create a new secret? (y/N)"
    if ($response -ne 'y') {
        Write-Host "Exiting." -ForegroundColor Yellow
        exit 0
    }
    $appId = $existingApps[0].appId
    $objectId = $existingApps[0].id
} else {
    # Create app with public client redirect URI for PnP PowerShell interactive login
    $appJson = az ad app create `
        --display-name "$AppName" `
        --sign-in-audience "AzureADMyOrg" `
        --public-client-redirect-uris "http://localhost" `
        --is-fallback-public-client true `
        --enable-id-token-issuance true `
        --only-show-errors `
        --output json

    $app = $appJson | ConvertFrom-Json

    $appId = $app.appId
    $objectId = $app.id
    Write-Host "  App created. Client ID: $appId" -ForegroundColor Green
}

# ── Add API permissions ────────────────────────────────────────

# 1. Microsoft Graph — Sites.Read.All (Application) — for .NET backend
Write-Host "`nAdding Microsoft Graph Sites.Read.All (Application) permission..." -ForegroundColor Cyan
az ad app permission add `
    --id $objectId `
    --api $graphAppId `
    --api-permissions "$graphSitesReadAllAppRoleId=Role" `
    --only-show-errors | Out-Null
Write-Host "  Permission added." -ForegroundColor Green

# 2. SharePoint — AllSites.Manage (Delegated) — for PnP PowerShell interactive login
Write-Host "Adding SharePoint AllSites.Manage (Delegated) permission..." -ForegroundColor Cyan
az ad app permission add `
    --id $objectId `
    --api $sharepointAppId `
    --api-permissions "$spAllSitesManageDelegatedId=Scope" `
    --only-show-errors | Out-Null
Write-Host "  Permission added." -ForegroundColor Green

# ── Grant admin consent ──────────────────────────────────────
Write-Host "`nGranting admin consent (requires Global Admin or Privileged Role Admin)..." -ForegroundColor Cyan

try {
    az ad app permission admin-consent --id $objectId --only-show-errors | Out-Null
    Write-Host "  Admin consent granted." -ForegroundColor Green
} catch {
    Write-Host "  WARNING: Could not grant admin consent automatically." -ForegroundColor Yellow
    Write-Host "  Ask your tenant admin to grant consent in the Azure Portal:" -ForegroundColor Yellow
    Write-Host "  Azure Portal > Entra ID > App Registrations > $AppName > API Permissions > Grant admin consent" -ForegroundColor Yellow
}

# ── Create a client secret ───────────────────────────────────
Write-Host "`nCreating client secret (valid for $SecretExpiryMonths months)..." -ForegroundColor Cyan

$endDate = (Get-Date).AddMonths($SecretExpiryMonths).ToString("yyyy-MM-ddTHH:mm:ssZ")

# Use Microsoft Graph REST API — reliably returns the secret value
$body = "{""passwordCredential"":{""displayName"":""SharePointListSearch"",""endDateTime"":""$endDate""}}"

$secretJson = az rest `
    --method POST `
    --uri "https://graph.microsoft.com/v1.0/applications/$objectId/addPassword" `
    --body $body `
    --only-show-errors `
    --output json

if (-not $secretJson) {
    Write-Host "  ERROR: Failed to create client secret." -ForegroundColor Red
    Write-Host "  Create one manually:" -ForegroundColor Yellow
    Write-Host "  Azure Portal > Entra ID > App Registrations > $AppName > Certificates & secrets" -ForegroundColor Yellow
    exit 1
}

$secret = $secretJson | ConvertFrom-Json
$clientSecret = $secret.secretText

if (-not $clientSecret) {
    Write-Host "  ERROR: Secret created but value not returned. Raw response:" -ForegroundColor Red
    Write-Host $secretJson -ForegroundColor Gray
    Write-Host "  Create one manually:" -ForegroundColor Yellow
    Write-Host "  Azure Portal > Entra ID > App Registrations > $AppName > Certificates & secrets" -ForegroundColor Yellow
    exit 1
}

Write-Host "  Secret created successfully." -ForegroundColor Green

# ── Create Service Principal (required for consent and app usage) ──
Write-Host "`nEnsuring Service Principal exists..." -ForegroundColor Cyan
$existingSp = az ad sp show --id $appId --only-show-errors 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    az ad sp create --id $appId --only-show-errors | Out-Null
    Write-Host "  Service Principal created." -ForegroundColor Green

    # Re-grant admin consent after SP creation
    try {
        az ad app permission admin-consent --id $objectId --only-show-errors | Out-Null
        Write-Host "  Admin consent re-granted." -ForegroundColor Green
    } catch {
        Write-Host "  Admin consent may still need to be granted manually." -ForegroundColor Yellow
    }
} else {
    Write-Host "  Service Principal already exists." -ForegroundColor Green
}

# ── Output results ───────────────────────────────────────────
Write-Host "`n" -NoNewline
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  App Registration Complete" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan

Write-Host "`n--- Copy these values into your .env file ---`n" -ForegroundColor Yellow

Write-Host "GRAPH_TENANT_ID=$tenantId"
Write-Host "GRAPH_CLIENT_ID=$appId"
Write-Host "GRAPH_CLIENT_SECRET=$clientSecret"

Write-Host "`n--- For PnP PowerShell, connect with ---`n" -ForegroundColor Yellow

Write-Host "Connect-PnPOnline -Url `"https://yourtenant.sharepoint.com/sites/yoursite`" -ClientId `"$appId`" -Interactive"

Write-Host "`n════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  IMPORTANT: Save the client secret now — it cannot be" -ForegroundColor Red
Write-Host "  retrieved again from the Azure Portal." -ForegroundColor Red
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

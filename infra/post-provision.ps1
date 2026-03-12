# Post-provision hook: writes azd outputs into .env
# Fetches API keys via CLI since Bicep listKeys() is blocked by subscription policy

Write-Host "Updating .env with provisioned resource values..."

$envFile = Join-Path $PSScriptRoot ".." ".env"
$content = Get-Content $envFile -Raw

# Fetch keys via Azure CLI (uses Entra ID auth, not local auth)
Write-Host "Fetching Search admin key..."
$searchKey = az search admin-key show --service-name $env:AZURE_SEARCH_NAME --resource-group $env:AZURE_RESOURCE_GROUP --query "primaryKey" -o tsv
Write-Host "Fetching AI API key..."
$aiKey = az cognitiveservices account keys list --name $env:AZURE_AI_NAME --resource-group $env:AZURE_RESOURCE_GROUP --query "key1" -o tsv

$replacements = @{
    'AZURE_SEARCH_ENDPOINT'             = $env:AZURE_SEARCH_ENDPOINT
    'AZURE_SEARCH_ADMIN_KEY'            = $searchKey
    'AZURE_AI_ENDPOINT'                 = $env:AZURE_AI_ENDPOINT
    'AZURE_AI_API_KEY'                  = $aiKey
    'AZURE_AI_EMBEDDING_DEPLOYMENT'     = $env:AZURE_AI_EMBEDDING_DEPLOYMENT
}

foreach ($key in $replacements.Keys) {
    $val = $replacements[$key]
    if ($val) {
        $content = $content -replace "(?m)^${key}=.*", "${key}=${val}"
    }
}

Set-Content $envFile $content -NoNewline
Write-Host "Done. Values written to .env"

#!/bin/bash
# Post-provision hook: writes azd outputs into .env
# Fetches API keys via CLI since Bicep listKeys() is blocked by subscription policy

echo "Updating .env with provisioned resource values..."

ENV_FILE="$(dirname "$0")/../.env"

# Fetch keys via Azure CLI (uses Entra ID auth, not local auth)
echo "Fetching Search admin key..."
SEARCH_KEY=$(az search admin-key show --service-name "$AZURE_SEARCH_NAME" --resource-group "$AZURE_RESOURCE_GROUP" --query "primaryKey" -o tsv)
echo "Fetching AI API key..."
AI_KEY=$(az cognitiveservices account keys list --name "$AZURE_AI_NAME" --resource-group "$AZURE_RESOURCE_GROUP" --query "key1" -o tsv)

# Update Azure Search values
sed -i "s|^AZURE_SEARCH_ENDPOINT=.*|AZURE_SEARCH_ENDPOINT=${AZURE_SEARCH_ENDPOINT}|" "$ENV_FILE"
sed -i "s|^AZURE_SEARCH_ADMIN_KEY=.*|AZURE_SEARCH_ADMIN_KEY=${SEARCH_KEY}|" "$ENV_FILE"

# Update Azure AI Foundry values
sed -i "s|^AZURE_AI_ENDPOINT=.*|AZURE_AI_ENDPOINT=${AZURE_AI_ENDPOINT}|" "$ENV_FILE"
sed -i "s|^AZURE_AI_API_KEY=.*|AZURE_AI_API_KEY=${AI_KEY}|" "$ENV_FILE"
sed -i "s|^AZURE_AI_EMBEDDING_DEPLOYMENT=.*|AZURE_AI_EMBEDDING_DEPLOYMENT=${AZURE_AI_EMBEDDING_DEPLOYMENT}|" "$ENV_FILE"

echo "Done. Values written to .env"

targetScope = 'subscription'

@description('Primary location for all resources')
param location string

@description('Name of the resource group')
param resourceGroupName string = ''

@description('Unique suffix for resource names')
param environmentName string

var abbrs = loadJsonContent('abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var rgName = !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourceGroup}${environmentName}'

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
}

module search 'modules/search.bicep' = {
  scope: rg
  params: {
    name: '${abbrs.searchService}${resourceToken}'
    location: location
  }
}

module openai 'modules/openai.bicep' = {
  scope: rg
  params: {
    name: '${abbrs.openAiAccount}${resourceToken}'
    location: location
    embeddingModelName: 'text-embedding-3-small'
    embeddingDeploymentName: 'text-embedding-3-small'
  }
}

output AZURE_SEARCH_ENDPOINT string = search.outputs.endpoint
output AZURE_SEARCH_NAME string = search.outputs.name
output AZURE_SEARCH_INDEX_NAME string = 'faq-index'
output AZURE_AI_ENDPOINT string = openai.outputs.endpoint
output AZURE_AI_NAME string = openai.outputs.name
output AZURE_AI_EMBEDDING_DEPLOYMENT string = 'text-embedding-3-small'
output AZURE_RESOURCE_GROUP string = rg.name

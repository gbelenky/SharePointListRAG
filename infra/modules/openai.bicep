@description('Name of the Azure OpenAI account')
param name string

@description('Location for the resource')
param location string

@description('Embedding model name')
param embeddingModelName string

@description('Embedding deployment name')
param embeddingDeploymentName string

resource openai 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openai
  name: embeddingDeploymentName
  sku: {
    name: 'GlobalStandard'
    capacity: 8 // 8K TPM — minimum
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: embeddingModelName
      version: '1'
    }
  }
}

output endpoint string = openai.properties.endpoint
output name string = openai.name

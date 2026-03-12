@description('Name of the Azure AI Search service')
param name string

@description('Location for the resource')
param location string

// Free tier: 1 index, 10K docs, 50MB — cheapest option
resource search 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: name
  location: location
  sku: {
    name: 'free'
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
  }
}

output endpoint string = 'https://${search.name}.search.windows.net'
output name string = search.name

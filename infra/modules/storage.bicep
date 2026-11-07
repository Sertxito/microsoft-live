param location string
param name string
param tags object
param loaderPrincipalId string
resource account 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: name
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Enabled'
    networkAcls: { defaultAction: 'Allow', bypass: 'None' }
    encryption: {
      keySource: 'Microsoft.Storage'
      services: { blob: { enabled: true }, file: { enabled: true } }
    }
  }
}
resource blob 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  name: 'default'
  parent: account
}
resource tutorials 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: 'tutorials'
  parent: blob
  properties: { publicAccess: 'None' }
}
resource write 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(tutorials.id, loaderPrincipalId, 'blob-write')
  scope: tutorials
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: loaderPrincipalId
    principalType: 'ServicePrincipal'
  }
}
output name string = account.name

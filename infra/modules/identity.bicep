param location string
param prefix string
param tags object
resource runtime 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'id-${prefix}-runtime'
  location: location
  tags: tags
}
resource loader 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'id-${prefix}-loader'
  location: location
  tags: tags
}
output runtimeName string = runtime.name
output runtimeClientId string = runtime.properties.clientId
output runtimePrincipalId string = runtime.properties.principalId
output loaderName string = loader.name
output loaderClientId string = loader.properties.clientId
output loaderPrincipalId string = loader.properties.principalId

param location string
param name string
param tags object
param sku string
param runtimePrincipalId string
param loaderPrincipalId string
resource search 'Microsoft.Search/searchServices@2023-11-01' = {
  name: name
  location: location
  tags: tags
  sku: { name: sku }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    publicNetworkAccess: 'enabled'
    disableLocalAuth: true
  }
}
resource reader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, runtimePrincipalId, 'query')
  scope: search
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '1407120a-92aa-4202-b7e9-c0e197c71c8f')
    principalId: runtimePrincipalId
    principalType: 'ServicePrincipal'
  }
}
var loaderRoles = [
  '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
  '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
]
resource writer 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for role in loaderRoles: {
  name: guid(search.id, loaderPrincipalId, role)
  scope: search
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role)
    principalId: loaderPrincipalId
    principalType: 'ServicePrincipal'
  }
}]
output name string = search.name
output endpoint string = 'https://${search.name}.search.windows.net'

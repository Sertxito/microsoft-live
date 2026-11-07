targetScope = 'resourceGroup'

@minLength(3)
@maxLength(16)
param environmentName string = 'm365live-demo'
param location string = resourceGroup().location
param owner string
@allowed(['basic', 'free'])
param searchSku string = 'basic'

var suffix = uniqueString(resourceGroup().id)
var tags = {
  project: 'microsoft-live'
  environment: environmentName
  purpose: 'isolated-demo'
  owner: owner
}

module identities 'modules/identity.bicep' = {
  name: 'identities'
  params: { location: location, prefix: environmentName, tags: tags }
}
module registry 'modules/registry.bicep' = {
  name: 'registry'
  params: {
    location: location
    name: 'cr${replace(environmentName, '-', '')}${suffix}'
    tags: tags
    runtimePrincipalId: identities.outputs.runtimePrincipalId
  }
}
module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    location: location
    name: 'st${take(replace(environmentName, '-', ''), 9)}${suffix}'
    tags: tags
    loaderPrincipalId: identities.outputs.loaderPrincipalId
  }
}
module search 'modules/search.bicep' = {
  name: 'search'
  params: {
    location: location
    name: 'srch-${environmentName}-${suffix}'
    tags: tags
    sku: searchSku
    runtimePrincipalId: identities.outputs.runtimePrincipalId
    loaderPrincipalId: identities.outputs.loaderPrincipalId
  }
}
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: { location: location, prefix: environmentName, tags: tags }
}
resource environment 'Microsoft.App/managedEnvironments@2025-07-01' = {
  name: 'cae-${environmentName}'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: monitoring.outputs.workspaceCustomerId
        sharedKey: monitoring.outputs.workspaceSharedKey
      }
    }
    workloadProfiles: [
      { name: 'Consumption', workloadProfileType: 'Consumption' }
    ]
  }
}

output registryName string = registry.outputs.name
output registryServer string = registry.outputs.loginServer
output storageName string = storage.outputs.name
output searchName string = search.outputs.name
output searchEndpoint string = search.outputs.endpoint
output runtimeIdentityName string = identities.outputs.runtimeName
output runtimeClientId string = identities.outputs.runtimeClientId
output loaderIdentityName string = identities.outputs.loaderName
output loaderClientId string = identities.outputs.loaderClientId
output loaderPrincipalId string = identities.outputs.loaderPrincipalId
output environmentName string = environment.name
output applicationInsightsName string = monitoring.outputs.insightsName

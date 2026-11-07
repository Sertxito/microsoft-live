targetScope = 'resourceGroup'

param location string = resourceGroup().location
param appName string = 'ca-m365live-demo'
param environmentName string = 'cae-m365live-demo'
param registryName string
param runtimeIdentityName string = 'id-m365live-demo-runtime'
param applicationInsightsName string = 'appi-m365live-demo'
param searchName string
param searchIndex string = 'tutorials'
@allowed(['Jwt', 'ApiKey'])
param authMode string = 'Jwt'
param authTenantId string = ''
param authAudience string = ''
@secure()
param apiKey string = ''
@minLength(1)
param revisionSuffix string
@description('Exact ACR image digest, never a mutable tag.')
param imageDigest string
@description('Previously accepted revision. Empty only for bootstrap, restricted to smokeClientCidr.')
param stableRevisionName string = ''
@description('Single operator IPv4 /32 allowed to reach the isolated demo.')
param smokeClientCidr string
@description('Explicitly approved additional connector allow rules; never replace the operator rule.')
param connectorIngressRules array = []
@minValue(0)
param searchMinimumScore int = 0
param tags object

resource environment 'Microsoft.App/managedEnvironments@2025-07-01' existing = { name: environmentName }
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = { name: runtimeIdentityName }
resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = { name: registryName }
resource insights 'Microsoft.Insights/components@2020-02-02' existing = { name: applicationInsightsName }
module app 'modules/container-apps.bicep' = {
  name: 'candidate'
  params: {
    location: location
    name: appName
    tags: tags
    environmentId: environment.id
    identityId: identity.id
    identityClientId: identity.properties.clientId
    registryServer: registry.properties.loginServer
    image: '${registry.properties.loginServer}/harness@${imageDigest}'
    authAuthority: '${az.environment().authentication.loginEndpoint}${authTenantId}/v2.0'
    authAudience: authAudience
    authMode: authMode
    apiKey: apiKey
    searchEndpoint: 'https://${searchName}.search.windows.net'
    searchIndex: searchIndex
    searchMinimumScore: string(searchMinimumScore)
    applicationInsightsConnectionString: insights.properties.ConnectionString
    revisionSuffix: revisionSuffix
    stableRevisionName: stableRevisionName
    smokeClientCidr: smokeClientCidr
    connectorIngressRules: connectorIngressRules
  }
}
output revisionName string = '${appName}--${revisionSuffix}'
output hostname string = app.outputs.hostname

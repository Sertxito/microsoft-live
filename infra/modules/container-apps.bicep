param location string
param name string
param tags object
param environmentId string
param identityId string
param identityClientId string
param registryServer string
param image string
param authAuthority string
param authAudience string
param authMode string
@secure()
param apiKey string
param searchEndpoint string
param searchIndex string
param searchMinimumScore string
@secure()
param applicationInsightsConnectionString string
param revisionSuffix string
param stableRevisionName string
param smokeClientCidr string
param connectorIngressRules array

resource app 'Microsoft.App/containerApps@2025-07-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identityId}': {} }
  }
  properties: {
    managedEnvironmentId: environmentId
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Multiple'
      ingress: {
        external: true
        allowInsecure: false
        targetPort: 8080
        transport: 'http'
        ipSecurityRestrictions: concat([{
          name: 'smoke-operator'
          ipAddressRange: smokeClientCidr
          action: 'Allow'
          description: 'Isolated demo access; widening requires separate approval.'
        }], connectorIngressRules)
        traffic: [{
          revisionName: empty(stableRevisionName) ? '${name}--${revisionSuffix}' : stableRevisionName
          weight: 100
        }]
      }
      registries: [{ server: registryServer, identity: identityId }]
      secrets: concat([{ name: 'appinsights', value: applicationInsightsConnectionString }],
        authMode == 'ApiKey' ? [{ name: 'api-key', value: apiKey }] : [])
    }
    template: {
      revisionSuffix: revisionSuffix
      containers: [{
        name: 'api'
        image: image
        resources: { cpu: json('0.25'), memory: '0.5Gi' }
        env: concat([
          { name: 'ASPNETCORE_HTTP_PORTS', value: '8080' }
          { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
          { name: 'HARNESS_MODE', value: 'AzureIntegrated' }
          { name: 'HARNESS_AUTH_MODE', value: authMode }
          { name: 'HARNESS_AUTHORITY', value: authAuthority }
          { name: 'HARNESS_AUTH_AUDIENCE', value: authAudience }
          { name: 'HARNESS_SEARCH_ENDPOINT', value: searchEndpoint }
          { name: 'HARNESS_SEARCH_INDEX', value: searchIndex }
          { name: 'HARNESS_SEARCH_MINIMUM_SCORE', value: searchMinimumScore }
          { name: 'HARNESS_MANAGED_IDENTITY_CLIENT_ID', value: identityClientId }
          { name: 'HARNESS_TELEMETRY_EXPORT', value: 'true' }
          { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', secretRef: 'appinsights' }
        ], authMode == 'ApiKey' ? [{ name: 'HARNESS_API_KEY', secretRef: 'api-key' }] : [])
        probes: [
          { type: 'Startup', tcpSocket: { port: 8080 }, periodSeconds: 5, failureThreshold: 30 }
          { type: 'Liveness', httpGet: { path: '/health/live', port: 8080 }, periodSeconds: 30, failureThreshold: 3 }
          { type: 'Readiness', tcpSocket: { port: 8080 }, periodSeconds: 10, failureThreshold: 3 }
        ]
      }]
      scale: { minReplicas: 0, maxReplicas: 1 }
    }
  }
}
output hostname string = app.properties.configuration.ingress.fqdn

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][guid] $SubscriptionId,
    [Parameter(Mandatory)][guid] $TenantId,
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9-]{3,40}$')][string] $Name,
    [string] $StatePath = (Join-Path $PSScriptRoot '..\.local\azure\entra.json'),
    [switch] $AuthorizeEntraChanges
)
$ErrorActionPreference = 'Stop'
if (-not $AuthorizeEntraChanges) { throw 'Entra writes require -AuthorizeEntraChanges. No Graph request was made.' }
if (-not $PSCmdlet.ShouldProcess("$TenantId / $Name", 'Create or reconcile API and Postman PKCE applications (no secrets or consent grants)')) { return }
. (Join-Path $PSScriptRoot 'azure-common.ps1')
Assert-AzureContext $SubscriptionId $TenantId
$graph = 'https://graph.microsoft.com/v1.0'
$apiName = "$Name-api"
$clientName = "$Name-postman"
$scopeId = '647b2e55-f883-4fbd-8237-fdc37f82b9df'
$roleId = 'd83c7cef-213a-40c9-982a-4f8d80ea2920'

function Get-DemoApplication {
    param([string] $DisplayName)
    $filter = [uri]::EscapeDataString("displayName eq '$DisplayName'")
    $response = Invoke-AzureCli @('rest', '--method', 'GET', '--url', "$graph/applications?`$filter=$filter", '-o', 'json')
    if (@($response.value).Count -gt 1) { throw "Ambiguous application name '$DisplayName'; no mutation allowed." }
    return @($response.value)[0]
}
function Assert-ManagedApplication {
    param($Application)
    if ($Application -and 'microsoft-live-isolated-demo' -notin @($Application.tags)) {
        throw 'Existing application was not created by this demo bootstrap; refusing to overwrite it.'
    }
}
function Ensure-ServicePrincipal {
    param([string] $AppId)
    $filter = [uri]::EscapeDataString("appId eq '$AppId'")
    $existing = Invoke-AzureCli @('rest', '--method', 'GET', '--url', "$graph/servicePrincipals?`$filter=$filter", '-o', 'json')
    if (@($existing.value).Count -gt 1) { throw 'Ambiguous service principal.' }
    if (@($existing.value).Count -eq 1) { return $existing.value[0] }
    return Invoke-AzureJsonBody POST "$graph/servicePrincipals" @{ appId = $AppId }
}

$api = Get-DemoApplication $apiName
Assert-ManagedApplication $api
if (-not $api) {
    $api = Invoke-AzureJsonBody POST "$graph/applications" @{
        displayName = $apiName; signInAudience = 'AzureADMyOrg'; tags = @('microsoft-live-isolated-demo')
    }
}
$apiBody = @{
    identifierUris = @("api://$($api.appId)")
    api = @{
        requestedAccessTokenVersion = 2
        oauth2PermissionScopes = @(@{
            id = $scopeId; value = 'Tutorials.Search'; type = 'User'; isEnabled = $true
            adminConsentDisplayName = 'Search demo tutorials'
            adminConsentDescription = 'Search only the isolated tutorial demo.'
            userConsentDisplayName = 'Search demo tutorials'
            userConsentDescription = 'Search only the isolated tutorial demo.'
        })
    }
    appRoles = @(@{
        id = $roleId; value = 'Tutorials.Search'; displayName = 'Search demo tutorials'
        description = 'Read tutorial search results in the isolated demo.'
        allowedMemberTypes = @('Application'); isEnabled = $true
    })
}
$null = Invoke-AzureJsonBody PATCH "$graph/applications/$($api.id)" $apiBody
$apiPrincipal = Ensure-ServicePrincipal $api.appId
$client = Get-DemoApplication $clientName
Assert-ManagedApplication $client
if (-not $client) {
    $client = Invoke-AzureJsonBody POST "$graph/applications" @{
        displayName = $clientName; signInAudience = 'AzureADMyOrg'; tags = @('microsoft-live-isolated-demo')
    }
}
$null = Invoke-AzureJsonBody PATCH "$graph/applications/$($client.id)" @{
    publicClient = @{ redirectUris = @('https://oauth.pstmn.io/v1/browser-callback') }
    requiredResourceAccess = @(@{
        resourceAppId = $api.appId; resourceAccess = @(@{ id = $scopeId; type = 'Scope' })
    })
}
$clientPrincipal = Ensure-ServicePrincipal $client.appId
$state = @{
    tenantId = $TenantId.ToString(); subscriptionId = $SubscriptionId.ToString()
    apiObjectId = $api.id; apiClientId = $api.appId; apiServicePrincipalId = $apiPrincipal.id
    postmanObjectId = $client.id; postmanClientId = $client.appId; postmanServicePrincipalId = $clientPrincipal.id
    audience = $api.appId; scope = "api://$($api.appId)/Tutorials.Search"
    authority = "https://login.microsoftonline.com/$TenantId/v2.0"
    redirectUri = 'https://oauth.pstmn.io/v1/browser-callback'
}
$parent = Split-Path -Parent ([IO.Path]::GetFullPath($StatePath))
$null = New-Item -ItemType Directory -Path $parent -Force
$state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $StatePath -Encoding utf8NoBOM
Write-Output "Non-secret application IDs saved at $StatePath. No role assignment, secret, token, or tenant-wide consent was created."

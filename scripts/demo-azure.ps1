[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Query,
    [string] $ApiKey,
    [string] $StatePath = (Join-Path $PSScriptRoot '..\.local\azure\candidate.json'),
    [switch] $AuthorizeRemote
)
$ErrorActionPreference = 'Stop'
if (-not $AuthorizeRemote) { throw 'Azure demo calls and optional secret retrieval require -AuthorizeRemote.' }
$state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
if ($state.authMode -ne 'ApiKey') { throw 'This command is for the explicitly selected API-key demo only.' }
. (Join-Path $PSScriptRoot 'azure-common.ps1')
Assert-AzureContext ([guid]$state.subscriptionId) ([guid]$state.tenantId)
Assert-DemoGroup $state.resourceGroup ([guid]$state.subscriptionId)
$app = Invoke-AzureCli @('containerapp','show','-g',$state.resourceGroup,'-n',$state.appName,'-o','json')
if ($app.tags.project -ne 'microsoft-live' -or -not $app.properties.configuration.ingress.fqdn) {
    throw 'Target is not the recorded isolated demo.'
}
if (-not $ApiKey) {
    $secrets = Invoke-AzureCli @('containerapp','secret','list','-g',$state.resourceGroup,
        '-n',$state.appName,'--show-values','-o','json')
    $ApiKey = @($secrets | Where-Object name -eq 'api-key')[0].value
    $secrets = $null
}
if ($ApiKey -notmatch '\A[0-9a-fA-F]{64}\z') { throw 'Configured demo key could not be obtained; no anonymous fallback is available.' }
$uri = "https://$($app.properties.configuration.ingress.fqdn)/api/tutorials/search"
$response = Invoke-WebRequest -Uri $uri -Method Post -Headers @{'X-API-Key'=$ApiKey} `
    -Body (@{query=$Query;audience='community';maxResults=5} | ConvertTo-Json) `
    -ContentType 'application/json' -SkipHttpErrorCheck -TimeoutSec 30 -MaximumRedirection 0
$ApiKey = $null
if ([int]$response.StatusCode -ne 200) { throw "Azure demo request returned $($response.StatusCode); inspect the correlated error without logging credentials." }
$result = $response.Content | ConvertFrom-Json
if ($result.correlationId -cne ($response.Headers['X-Correlation-ID'] -join '') -or
    $null -ne $result.generatedAnswer) { throw 'Azure response violates correlation or retrieval-only contract.' }
$result | ConvertTo-Json -Depth 15

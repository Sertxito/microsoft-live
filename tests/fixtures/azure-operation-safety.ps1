param([Parameter(Mandatory)][string] $Scenario)
$ErrorActionPreference = 'Stop'
$global:DemoFixture = @{
    Scenario=$Scenario; CliCalls=0; HttpCalls=0; Mutations=0
    BlobWrites=0; DocumentWrites=0; SchemaWrites=0; IndexExists=($Scenario -ne 'LoadNew')
    Subscription='11111111-1111-1111-1111-111111111111'; Tenant='22222222-2222-2222-2222-222222222222'
    Candidate='ca-fixture--candidate'; Previous='ca-fixture--stable'; Current='ca-fixture--stable'
}
if ($Scenario -eq 'Rollback') { $global:DemoFixture.Current = $global:DemoFixture.Candidate }
if ($Scenario -eq 'StaleTraffic') { $global:DemoFixture.Current = 'ca-fixture--newer' }
function global:az {
    $f = $global:DemoFixture
    $f.CliCalls++
    $a = @($args)
    $global:LASTEXITCODE = 0
    $command = $a[0..1] -join ' '
    $result = switch ($command) {
        'account show' { @{id=$f.Subscription; tenantId=$f.Tenant; state='Enabled'}; break }
        'account get-access-token' {
            $oid = if ($f.Scenario -eq 'WrongLoader') { $f.Subscription } else { $f.Tenant }
            $payload = @{oid=$oid;tid=$f.Tenant} | ConvertTo-Json -Compress
            $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload)).TrimEnd('=').Replace('+','-').Replace('/','_')
            @{accessToken="fixture.$encoded.fixture"}
            break
        }
        'group show' { @{location='westeurope'; tags=@{project='microsoft-live'; purpose='isolated-demo'}}; break }
        'containerapp show' {
            if ($f.Scenario.StartsWith('Network')) { $f.App; break }
            @{tags=@{project='microsoft-live'}; properties=@{configuration=@{
                activeRevisionsMode='Multiple'; ingress=@{traffic=@(@{revisionName=$f.Current;weight=100})}
            }}}
            break
        }
        'containerapp list' { @($f.App); break }
        'containerapp revision' {
            if ($a[2] -ne 'show') { throw 'Unexpected revision operation in fixture.' }
            $revision = $a[[Array]::IndexOf($a, '--revision') + 1]
            @{properties=@{
                active=$true; fqdn='candidate.example.invalid'
                template=@{containers=@(@{image=$(if ($f.Scenario.StartsWith('CandidateConnector')) {
                    'registry.example.invalid/harness@sha256:' + ('a' * 64)
                } else {"registry.example.invalid/harness@$revision"})})}
            }}
            break
        }
        'containerapp ingress' {
            if (($a[2..3] -join ' ') -ne 'traffic set') { throw 'Unexpected ingress operation in fixture.' }
            $f.Current = $a[[Array]::IndexOf($a,'--revision-weight')+1].Split('=')[0]
            $f.Mutations++
            @{}
            break
        }
        'rest --method' {
            $method = $a[[Array]::IndexOf($a,'--method')+1]
            $uri = $a[[Array]::IndexOf($a,'--url')+1]
            if ($f.Scenario.StartsWith('Network')) {
                if ($method -ne 'PATCH' -or $uri -ne "https://management.azure.com$($f.App.id)?api-version=2025-07-01") {
                    throw 'Fixture blocked unexpected network mutation.'
                }
                $bodyPath = $a[[Array]::IndexOf($a,'--body')+1].TrimStart('@')
                $body = Get-Content -LiteralPath $bodyPath -Raw | ConvertFrom-Json
                if (@($body.properties.PSObject.Properties).Count -ne 1 -or
                    @($body.properties.configuration.PSObject.Properties).Count -ne 1) {
                    throw 'Network mutation contained non-ingress properties.'
                }
                $f.App.properties.configuration.ingress = $body.properties.configuration.ingress
                $f.Mutations++
                $f.App
                break
            }
            if ($uri -notlike 'https://srch-fixture.search.windows.net/*') { throw 'Fixture blocked unexpected REST destination.' }
            if ($method -eq 'GET' -and $uri -match '/indexes\?') {
                @{value=$(if ($f.IndexExists) { @($f.Schema) } else { @() })}
            } elseif ($method -eq 'PUT' -and $uri -match '/indexes/tutorials\?') {
                $f.SchemaWrites++; $f.IndexExists=$true; $f.Schema
            } elseif ($method -eq 'POST' -and $uri -match '/docs/search\?') {
                $count = if ($f.Scenario -eq 'CatalogOverflow') { 21 } else { $f.Catalog.Count }
                @{'@odata.count'=$count;value=@($f.Catalog | ForEach-Object {@{id=$_.id}})}
            } elseif ($method -eq 'POST' -and $uri -match '/docs/index\?') {
                $f.DocumentWrites++
                @{value=@($f.Catalog | ForEach-Object {@{key=$_.id;status=($f.Scenario -ne 'BatchFailure');statusCode=200}})}
            } else { throw "Fixture blocked unexpected Search operation: $method $uri" }
            break
        }
        'storage blob' {
            if ($a[2] -ne 'upload') { throw 'Unexpected Blob operation in fixture.' }
            $f.BlobWrites++
            @{}
            break
        }
        'network list-service-tags' {
            $names = @('AzureConnectors.NorthEurope','AzureConnectors.WestEurope','PowerPlatformPlex.NorthEurope','PowerPlatformPlex.WestEurope')
            if ($f.Scenario -eq 'NetworkMissingTag') { $names = $names[0..2] }
            $index = 0
            @{values=@(foreach ($name in $names) {
                $index++
                @{name=$name;properties=@{addressPrefixes=@("192.0.2.$index/32",'2001:db8::/64')}}
            })}
            break
        }
        'acr show' { @{name='crfixture';tags=@{project='microsoft-live'}}; break }
        'acr repository' { @{}; break }
        'deployment group' {
            if ($a[2] -ne 'validate') { throw 'Fixture blocked real candidate deployment.' }
            $path = $a[[Array]::IndexOf($a,'--parameters')+1].TrimStart('@')
            $p = (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).parameters
            if ($p.connectorIngressRules.value.Count -ne 1 -or
                $p.connectorIngressRules.value[0].ipAddressRange -ne '192.0.2.2/32' -or
                $p.smokeClientCidr.value -ne '192.0.2.1/32') { throw 'Candidate did not retain recorded operator and connector rules.' }
            $f.CandidateValidations = 1
            @{}; break
        }
        default { throw "Fixture blocked unexpected Azure CLI command: $command" }
    }
    $result | ConvertTo-Json -Depth 30 -Compress
}
function global:Invoke-WebRequest {
    param($Uri, $Headers, $Body, [switch] $SkipHttpErrorCheck, $TimeoutSec, $MaximumRedirection, $Method, $ContentType)
    $f = $global:DemoFixture
    $f.HttpCalls++
    if (([uri]$Uri).Host -ne 'candidate.example.invalid') { throw 'Fixture blocked unexpected destination.' }
    $id = [guid]::NewGuid().ToString('D')
    $status = 200
    $value = @{status='ready'}
    $path = ([uri]$Uri).AbsolutePath
    if ($path -eq '/health/live') { $value = @{status='live'} }
    elseif (-not $Headers.Authorization -and -not $Headers['X-API-Key']) { $status=401 }
    elseif ($Headers['X-API-Key'] -eq 'invalid-key' -and $f.Scenario -ne 'KeyBypass') { $status=401 }
    elseif ($Headers.Authorization -eq 'Bearer fixture-forbidden' -and $f.Scenario -ne 'ForbiddenBypass') { $status=403 }
    elseif ($path -eq '/health/ready' -and $f.Scenario -eq 'FailedSmoke') { $status=503 }
    elseif ($path -eq '/api/capabilities') {
        $revision = if ($f.Scenario -eq 'WrongRevision') { 'ca-fixture--other' } else { $f.Candidate }
        $authMode = if ($f.Scenario -in @('KeyPromote','KeyBypass','McpPromote','McpFailedSmoke','McpPromoteRelativeState')) {'ApiKey'} else {'Jwt'}
        $value = @{capabilities=@('buscar_tutoriales'); revision=$revision; mode='AzureIntegrated'; authMode=$authMode}
    }
    elseif ($Body -eq '{"query":"ab"}') { $status=400 }
    elseif ($path -eq '/api/tutorials/search') {
        $value = @{correlationId=$id; generatedAnswer=$null; results=@(@{id='tutorial-001';source='https://example.invalid/tutorials/tutorial-001'})}
    }
    elseif ($path -eq '/mcp') {
        $rpc=$Body | ConvertFrom-Json
        $rpcResult=switch ($rpc.method) {
            'initialize' { @{protocolVersion='2025-03-26';capabilities=@{tools=@{}}} }
            'notifications/initialized' { $status=202; @{} }
            'tools/list' { @{tools=@(@{name='buscar_tutoriales';inputSchema=@{required=@('query')}})} }
            'tools/call' {
                if ($f.Scenario -eq 'McpFailedSmoke') { @{isError=$true;structuredContent=@{code='search_unavailable'}} }
                elseif ($rpc.params.arguments.query -eq 'ab') { @{isError=$true;structuredContent=@{code='validation_error'}} }
                else { @{isError=$false;structuredContent=@{correlationId=$id;generatedAnswer=$null;results=@(@{id='tutorial-001';source='https://example.invalid/tutorial-001'})}} }
            }
            default { throw 'Fixture rejected unknown MCP method.' }
        }
        $value=@{jsonrpc='2.0';id=$rpc.id;result=$rpcResult}
    }
    if ($status -ge 400) { $value=@{code='fixture_error'; message='Fixture'; correlationId=$id} }
    [pscustomobject]@{StatusCode=$status; Headers=@{'X-Correlation-ID'=$id}; Content=($value | ConvertTo-Json -Depth 10 -Compress)}
}
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$temporary = Join-Path ([IO.Path]::GetTempPath()) "demo-fixture-$([guid]::NewGuid().ToString('N'))"
$null = New-Item -ItemType Directory -Path $temporary
try {
    $statePath = Join-Path $temporary 'candidate.json'
    $f = $global:DemoFixture
    $f.Schema = Get-Content (Join-Path $root 'infra\search-index.json') -Raw | ConvertFrom-Json
    $f.Catalog = @(Get-Content (Join-Path $root 'knowledge\tutorials\catalog.json') -Raw | ConvertFrom-Json)
    if ($Scenario -eq 'SchemaMismatch') { $f.Schema.fields[0].type='Edm.Int32' }
    $foundationPath = Join-Path $temporary 'foundation.json'
    @{
        subscriptionId=$f.Subscription;tenantId=$f.Tenant;resourceGroup='rg-fixture'
        searchName=@{value='srch-fixture'};storageName=@{value='stfixture'}
    } | ConvertTo-Json | Set-Content -LiteralPath $foundationPath -Encoding utf8NoBOM
    $state = @{
        subscriptionId=$f.Subscription; tenantId=$f.Tenant; resourceGroup='rg-fixture'; appName='ca-fixture'
        candidateRevision=$f.Candidate; candidateImage="registry.example.invalid/harness@$($f.Candidate)"
        previousRevision=$f.Previous; previousImage="registry.example.invalid/harness@$($f.Previous)"
        baseUri='https://candidate.example.invalid/'
    }
    if ($Scenario -eq 'NoPrevious') { $state.previousRevision=''; $state.previousImage='' }
    if ($Scenario -in @('KeyPromote','KeyWrongMode','KeyBypass','McpPromote','McpFailedSmoke','McpPromoteRelativeState')) { $state.authMode='ApiKey' }
    if ($Scenario -in @('McpPromote','McpFailedSmoke','McpPromoteRelativeState')) { $state.mcpRequired=$true }
    $state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM
    $context = @{SubscriptionId=$f.Subscription; TenantId=$f.Tenant}
    $scriptName = 'set-demo-traffic.ps1'
    $parameters = $context.Clone()
    if ($Scenario.StartsWith('Network')) {
        $scriptName = 'set-copilot-access.ps1'
        $parameters.ResourceGroup = 'rg-fixture'; $parameters.AppName = 'ca-fixture'
        $parameters.ReceiptPath = Join-Path $temporary 'copilot-access.json'
        $parameters.Action = if ($Scenario -eq 'NetworkPreview') {'Preview'} else {'Apply'}
        if ($Scenario -ne 'NetworkGate') { $parameters.AuthorizeNetworkChanges = $true }
        $f.App = @{
            id="/subscriptions/$($f.Subscription)/resourceGroups/rg-fixture/providers/Microsoft.App/containerApps/ca-fixture"
            tags=@{project='microsoft-live'}
            identity=@{type='UserAssigned'}
            properties=@{
                provisioningState='Succeeded'
                latestRevisionName=$f.Current
                template=@{containers=@(@{image='fixture-image';env=@(
                    @{name='HARNESS_AUTH_MODE';value='ApiKey'},@{name='HARNESS_API_KEY';secretRef='api-key'}
                )})}
                configuration=@{
                    secrets=@(@{name='api-key'}); activeRevisionsMode='Multiple'
                    ingress=@{external=$true;allowInsecure=$false;traffic=@(@{revisionName=$f.Current;weight=100})
                        ipSecurityRestrictions=@(@{name='smoke-operator';ipAddressRange='192.0.2.200/32';action='Allow'})}
                }
            }
        }
        if ($Scenario -eq 'NetworkDenied') { $f.App.properties.configuration.ingress.ipSecurityRestrictions[0].action='Deny' }
    }
    switch ($Scenario) {
        { $_.StartsWith('Network') } { }
        'EntraGate' { $scriptName='prepare-entra.ps1'; $parameters.Name='fixture' }
        'FoundationGate' { $scriptName='deploy-foundation.ps1'; $parameters.ResourceGroup='rg-fixture'; $parameters.Owner='fixture' }
        'LoaderGate' {
            $scriptName='load-azure-knowledge.ps1'; $parameters.ResourceGroup='rg-fixture'
            $parameters.ExpectedLoaderPrincipalId=$f.Tenant; $parameters.SearchName='srch-fixture'; $parameters.StorageName='stfixture'
        }
        { $_ -in @('Load','LoadNew','LoadRerun','SchemaMismatch','WrongLoader','BatchFailure','CatalogOverflow') } {
            $scriptName='load-azure-knowledge.ps1'; $parameters.ResourceGroup='rg-fixture'
            $parameters.ExpectedLoaderPrincipalId=$f.Tenant; $parameters.SearchName='srch-fixture'; $parameters.StorageName='stfixture'
            $parameters.FoundationPath=$foundationPath; $parameters.AuthorizeDataUpload=$true
        }
        'BuildGate' { $scriptName='build-azure-image.ps1'; $parameters.ResourceGroup='rg-fixture'; $parameters.RegistryName='crfixture' }
        'CandidateGate' {
            $scriptName='deploy-candidate.ps1'; $parameters.ResourceGroup='rg-fixture'
            $parameters.ImageDigest='sha256:' + ('a' * 64); $parameters.RevisionSuffix='candidate'; $parameters.SmokeClientCidr='192.0.2.1/32'
        }
        { $_.StartsWith('CandidateConnector') } {
            $scriptName='deploy-candidate.ps1'; $parameters.ResourceGroup='rg-fixture'; $parameters.AppName='ca-fixture'
            $parameters.ImageDigest='sha256:' + ('b' * 64); $parameters.RevisionSuffix='candidate'; $parameters.SmokeClientCidr='192.0.2.1/32'
            $parameters.AuthMode='ApiKey'; $parameters.ApiKey=('a' * 64)
            $parameters.Action='Validate'; $parameters.AuthorizeRemoteValidation=$true
            $parameters.StatePath=$statePath; $parameters.FoundationPath=$foundationPath
            $connector=@{name='copilot-fixture';ipAddressRange='192.0.2.2/32';action='Allow'}
            @{
                subscriptionId=$f.Subscription;tenantId=$f.Tenant;resourceGroup='rg-fixture';appName='ca-fixture'
                rules=@($connector)
            } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $temporary 'copilot-access.json')
            @{revision=$f.Current;image=('registry.example.invalid/harness@sha256:' + ('a' * 64))} |
                ConvertTo-Json | Set-Content (Join-Path $temporary 'traffic-promote.json')
            $foundation = Get-Content $foundationPath -Raw | ConvertFrom-Json
            $foundation | Add-Member registryName @{value='crfixture'}
            $foundation | ConvertTo-Json -Depth 10 | Set-Content $foundationPath
            $f.App=@{name='ca-fixture';tags=@{project='microsoft-live'};properties=@{configuration=@{
                activeRevisionsMode='Multiple';ingress=@{
                    traffic=@(@{revisionName=$f.Current;weight=100})
                    ipSecurityRestrictions=@(@{name='smoke-operator';ipAddressRange='192.0.2.1/32';action='Allow'},$connector)
                }
            }}}
            if ($Scenario -eq 'CandidateConnectorDrift') {
                $f.App.properties.configuration.ingress.ipSecurityRestrictions=@(@{ipAddressRange='192.0.2.1/32';action='Allow'})
            }
        }
        'RbacGate' {
            $scriptName='grant-demo-loader.ps1'; $parameters.ResourceGroup='rg-fixture'; $parameters.PrincipalId=$f.Tenant
            $parameters.PrincipalType='User'; $parameters.SearchName='srch-fixture'; $parameters.StorageName='stfixture'
        }
        default {
            $parameters.Action = if ($Scenario -in @('Rollback','NoPrevious')) { 'Rollback' } else { 'Promote' }
            $parameters.StatePath = $statePath
            if ($Scenario -ne 'TrafficGate') {
                $parameters.AuthorizeAzureChanges=$true; $parameters.AuthorizeRemoteSmoke=$true
                $parameters.BearerToken='fixture-permitted'; $parameters.ForbiddenBearerToken='fixture-forbidden'
                if ($Scenario -in @('KeyPromote','KeyWrongMode','KeyBypass','McpPromote','McpFailedSmoke','McpPromoteRelativeState')) {
                    $parameters.Remove('BearerToken');$parameters.Remove('ForbiddenBearerToken');$parameters.ApiKey=('a' * 64)
                }
            }
        }
    }
    $failure = $null
    if ($Scenario -eq 'McpPromoteRelativeState') { Set-Location $temporary; $parameters.StatePath='candidate.json' }
    try {
        & (Join-Path $root "scripts\$scriptName") @parameters
        if ($Scenario -eq 'LoadRerun') { & (Join-Path $root "scripts\$scriptName") @parameters }
        if ($Scenario -eq 'NetworkApply') { & (Join-Path $root "scripts\$scriptName") @parameters }
    } catch { $failure=$_.Exception.Message }
    if ($Scenario -eq 'CandidateConnectorPreserved') {
        if ($failure -or $f.Mutations -ne 0 -or $f.CandidateValidations -ne 1) {
            throw "Expected connector-preserving candidate validation: $failure"
        }
    } elseif ($Scenario -in @('NetworkPreview','NetworkApply')) {
        $expectedMutations = if ($Scenario -eq 'NetworkApply') {1} else {0}
        if ($failure -or $f.Mutations -ne $expectedMutations) { throw "Unexpected network result: $failure" }
        if ($Scenario -eq 'NetworkApply') {
            $receipt = Get-Content -LiteralPath $parameters.ReceiptPath -Raw | ConvertFrom-Json
            if ($receipt.rules.Count -ne 5 -or $receipt.rules[0].ipAddressRange -ne '192.0.2.200/32' -or
                @($receipt.rules | Where-Object { $_.ipAddressRange -match ':' -or $_.action -ne 'Allow' }).Count) {
                throw 'Connector access receipt did not preserve operator access and IPv4 allow rules.'
            }
        } elseif (Test-Path -LiteralPath $parameters.ReceiptPath) { throw 'Preview persisted success-shaped access receipt.' }
    } elseif ($Scenario -in @('Load','LoadNew','LoadRerun')) {
        $expectedWrites = if ($Scenario -eq 'LoadRerun') { 2 } else { 1 }
        $expectedSchemaWrites = if ($Scenario -eq 'LoadNew') { 1 } else { 0 }
        if ($failure -or $f.BlobWrites -ne $expectedWrites -or $f.DocumentWrites -ne $expectedWrites -or
            $f.SchemaWrites -ne $expectedSchemaWrites) { throw "Expected idempotent catalog load, got: $failure" }
    } elseif ($Scenario -in @('Promote','Rollback','KeyPromote','McpPromote','McpPromoteRelativeState')) {
        if ($failure -or $f.Mutations -ne 1) { throw "Expected one successful traffic change, got $($f.Mutations): $failure" }
        $expected = if ($Scenario -eq 'Rollback') { $f.Previous } else { $f.Candidate }
        if ($f.Current -cne $expected) { throw 'Wrong revision received traffic.' }
        if ($Scenario -eq 'McpPromoteRelativeState' -and -not (Test-Path (Join-Path $temporary 'traffic-promote.json'))) {
            throw 'Relative candidate path resolved receipt outside the selected PowerShell directory.'
        }
    } else {
        if (-not $failure -or $f.Mutations -ne 0) { throw "Expected explicit rejection and zero traffic writes: $failure" }
        $expectedError = switch ($Scenario) {
            'EntraGate' {'-AuthorizeEntraChanges'}
            'NetworkGate' {'-AuthorizeNetworkChanges'}
            'NetworkMissingTag' {'All four official Europe service tags'}
            'NetworkDenied' {'Expected existing allow-list'}
            'FoundationGate' {'-AuthorizeRemoteValidation'}
            'LoaderGate' {'-AuthorizeDataUpload'}
            'BuildGate' {'-AuthorizeSourceUpload'}
            'CandidateGate' {'-AuthorizeAzureChanges'}
            'CandidateConnectorDrift' {'cannot change existing network access'}
            'RbacGate' {'-AuthorizeRbacChanges'}
            'TrafficGate' {'-AuthorizeAzureChanges'}
            'FailedSmoke' {'expected 200, got 503'}
            'WrongRevision' {'different revision'}
            'StaleTraffic' {'Traffic changed since'}
            'NoPrevious' {'known previously accepted'}
            'ForbiddenBypass' {'expected 403, got 200'}
            'SchemaMismatch' {'Existing index schema differs'}
            'WrongLoader' {'specifically authorized loader principal'}
            'BatchFailure' {'incomplete document batch'}
            'CatalogOverflow' {'20-document demo limit'}
            'KeyWrongMode' {'different authentication mode'}
            'KeyBypass' {'expected 401, got 200'}
            'McpFailedSmoke' {'MCP search tool reported an error (code search_unavailable)'}
        }
        if (-not $failure.Contains($expectedError)) { throw "Unexpected rejection for ${Scenario}: $failure" }
        if ($Scenario.EndsWith('Gate') -and ($f.CliCalls -ne 0 -or $f.HttpCalls -ne 0)) { throw 'Unauthorized script reached a remote adapter.' }
        if ($Scenario -in @('SchemaMismatch','WrongLoader','CatalogOverflow') -and
            ($f.BlobWrites -ne 0 -or $f.DocumentWrites -ne 0 -or $f.SchemaWrites -ne 0)) { throw 'Rejected load still wrote data.' }
    }
    Write-Output "Fixture passed: $Scenario (CLI and HTTP mocked; no Azure access)."
} finally {
    Set-Location $root
    Remove-Item -LiteralPath $temporary -Recurse -Force
    Remove-Item Function:\az, Function:\Invoke-WebRequest
    Remove-Variable DemoFixture -Scope Global
}

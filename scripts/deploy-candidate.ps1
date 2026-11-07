[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][guid] $SubscriptionId,
    [Parameter(Mandatory)][guid] $TenantId,
    [Parameter(Mandatory)][string] $ResourceGroup,
    [Parameter(Mandatory)][ValidatePattern('^sha256:[a-f0-9]{64}$')][string] $ImageDigest,
    [Parameter(Mandatory)][ValidatePattern('^[a-z][a-z0-9-]{0,40}[a-z0-9]$')][string] $RevisionSuffix,
    [Parameter(Mandatory)][string] $SmokeClientCidr,
    [string] $AppName = 'ca-m365live-demo',
    [ValidateSet('Jwt','ApiKey')][string] $AuthMode = 'Jwt',
    [string] $ApiKey,
    [switch] $RequireMcpSmoke,
    [ValidateSet('Validate','WhatIf','Deploy')][string] $Action = 'Deploy',
    [string] $FoundationPath = (Join-Path $PSScriptRoot '..\.local\azure\foundation.json'),
    [string] $EntraPath = (Join-Path $PSScriptRoot '..\.local\azure\entra.json'),
    [string] $StatePath = (Join-Path $PSScriptRoot '..\.local\azure\candidate.json'),
    [switch] $AuthorizeAzureChanges,
    [switch] $AuthorizeBootstrap,
    [switch] $AuthorizeRemoteValidation
)
$ErrorActionPreference = 'Stop'
if ($Action -eq 'Deploy' -and -not $AuthorizeAzureChanges) { throw 'Candidate deployment requires -AuthorizeAzureChanges.' }
if ($Action -ne 'Deploy' -and -not $AuthorizeRemoteValidation) { throw 'Candidate preflight requires -AuthorizeRemoteValidation.' }
if ($AuthMode -eq 'ApiKey' -and $ApiKey -notmatch '\A[0-9a-fA-F]{64}\z') {
    throw 'ApiKey mode requires the explicitly supplied 256-bit hexadecimal secret; it is never generated silently.'
}
$StatePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($StatePath)
$parts = $SmokeClientCidr.Split('/')
$ip = $null
if ($parts.Count -ne 2 -or $parts[1] -ne '32' -or -not [Net.IPAddress]::TryParse($parts[0], [ref]$ip) -or
    $ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
    throw 'SmokeClientCidr must be one explicitly authorized IPv4 /32 address.'
}
if (-not $PSCmdlet.ShouldProcess("$ResourceGroup / $AppName--$RevisionSuffix", "$Action restricted candidate; preserve accepted revision traffic")) { return }
. (Join-Path $PSScriptRoot 'azure-common.ps1')
Assert-AzureContext $SubscriptionId $TenantId
Assert-DemoGroup $ResourceGroup $SubscriptionId
$foundation = Get-Content -LiteralPath $FoundationPath -Raw | ConvertFrom-Json
$connectorRules = @()
$accessPath = Join-Path (Split-Path ([IO.Path]::GetFullPath($StatePath))) 'copilot-access.json'
if (Test-Path -LiteralPath $accessPath) {
    $access = Get-Content -LiteralPath $accessPath -Raw | ConvertFrom-Json
    if ($access.subscriptionId -ne $SubscriptionId.ToString() -or $access.tenantId -ne $TenantId.ToString() -or
        $access.resourceGroup -ne $ResourceGroup -or $access.appName -ne $AppName) {
        throw 'Connector network receipt differs from the deployment target.'
    }
    $connectorRules = @($access.rules | Where-Object name -like 'copilot-*')
    if (@($connectorRules | Where-Object { $_.action -ne 'Allow' -or $_.ipAddressRange -eq '0.0.0.0/0' }).Count) {
        throw 'Connector receipt contains unsupported network access.'
    }
}
$entra = $null
if ($AuthMode -eq 'Jwt') {
    $entra = Get-Content -LiteralPath $EntraPath -Raw | ConvertFrom-Json
    $actualAudience = [guid]::Empty
    if ($entra.tenantId -ne $TenantId.ToString() -or $entra.subscriptionId -ne $SubscriptionId.ToString() -or
        -not [guid]::TryParse($entra.audience, [ref]$actualAudience)) {
        throw 'Entra state differs from the authorized target or lacks an actual v2 token audience.'
    }
}
$apps = Invoke-AzureCli @('containerapp', 'list', '-g', $ResourceGroup, '-o', 'json')
$current = @($apps | Where-Object name -eq $AppName)
if ($current.Count -gt 1) { throw 'Ambiguous app.' }
$stable = ''
$stableImage = ''
if ($current.Count -eq 1) {
    if ($current[0].tags.project -ne 'microsoft-live' -or $current[0].properties.configuration.activeRevisionsMode -ne 'Multiple') {
        throw 'Existing application is not the isolated multi-revision demo.'
    }
    $traffic = @($current[0].properties.configuration.ingress.traffic | Where-Object weight -gt 0)
    if ($traffic.Count -ne 1 -or $traffic[0].weight -ne 100 -or -not $traffic[0].revisionName) {
        throw 'Traffic must name one accepted revision at 100%; refusing to guess stable or use latestRevision.'
    }
    $stable = $traffic[0].revisionName
    $accepted = Invoke-AzureCli @('containerapp', 'revision', 'show', '-g', $ResourceGroup, '-n', $AppName, '--revision', $stable, '-o', 'json')
    if (-not $accepted.properties.active) { throw 'Accepted revision is inactive.' }
    $stableImage = $accepted.properties.template.containers[0].image
    $receiptDirectory = Split-Path ([IO.Path]::GetFullPath($StatePath))
    $receipts = @('traffic-promote.json','traffic-rollback.json') |
        ForEach-Object { Join-Path $receiptDirectory $_ } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Get-Item | Sort-Object LastWriteTimeUtc -Descending
    if (-not $receipts) { throw 'Existing revision has no acceptance receipt. Smoke/promote the bootstrap before deploying another candidate.' }
    $receipt = Get-Content -LiteralPath @($receipts)[0].FullName -Raw | ConvertFrom-Json
    if ($receipt.revision -cne $stable -or $receipt.image -cne $stableImage -or
        $stableImage -notmatch '/harness@sha256:[a-f0-9]{64}$') {
        throw 'Current revision is not the immutable revision recorded by the latest accepted traffic operation.'
    }
    $restrictions = @($current[0].properties.configuration.ingress.ipSecurityRestrictions)
    $expectedRanges = @($SmokeClientCidr) + @($connectorRules.ipAddressRange)
    if (@(Compare-Object @($expectedRanges | Sort-Object) @($restrictions.ipAddressRange | Sort-Object)).Count -or
        @($restrictions | Where-Object action -ne 'Allow').Count) {
        throw 'Candidate deployment cannot change existing network access. Approve a separate access change first.'
    }
} elseif (-not $AuthorizeBootstrap) {
    throw 'No accepted revision exists. First bootstrap requires -AuthorizeBootstrap and is reachable only from SmokeClientCidr.'
}
$revision = "$AppName--$RevisionSuffix"
if ($stable -eq $revision) { throw 'Candidate suffix must differ from the accepted revision.' }
$registry = Invoke-AzureCli @('acr', 'show', '-g', $ResourceGroup, '-n', $foundation.registryName.value, '-o', 'json')
if ($registry.tags.project -ne 'microsoft-live') { throw 'Image registry is not a demo resource.' }
$null = Invoke-AzureCli @('acr', 'repository', 'show', '-n', $registry.name, '--image', "harness@$ImageDigest", '-o', 'json')
$group = Invoke-AzureCli @('group', 'show', '-n', $ResourceGroup, '-o', 'json')
$parameters = @{
    location = @{value='westeurope'}; appName = @{value=$AppName}
    environmentName = @{value=$foundation.environmentName.value}
    registryName = @{value=$registry.name}; runtimeIdentityName = @{value=$foundation.runtimeIdentityName.value}
    applicationInsightsName = @{value=$foundation.applicationInsightsName.value}
    searchName = @{value=$foundation.searchName.value}; authTenantId = @{value=$TenantId.ToString()}
    authAudience = @{value=$(if ($entra) {$entra.audience} else {''})}; revisionSuffix = @{value=$RevisionSuffix}
    authMode = @{value=$AuthMode}; apiKey = @{value=$(if ($AuthMode -eq 'ApiKey') {$ApiKey} else {''})}
    imageDigest = @{value=$ImageDigest}; stableRevisionName = @{value=$stable}
    smokeClientCidr = @{value=$SmokeClientCidr}; tags = @{value=$group.tags}
    connectorIngressRules = @{value=@($connectorRules)}
}
$file = [IO.Path]::GetTempFileName()
try {
    if ($IsWindows) {
        $acl = Get-Acl -LiteralPath $file
        $acl.SetAccessRuleProtection($true, $false)
        $rule = [Security.AccessControl.FileSystemAccessRule]::new(
            [Security.Principal.WindowsIdentity]::GetCurrent().User, 'FullControl', 'Allow')
        $acl.SetAccessRule($rule)
        Set-Acl -LiteralPath $file -AclObject $acl
    } else { & chmod 600 $file; if ($LASTEXITCODE) { throw 'Cannot protect temporary secure deployment parameters.' } }
    @{parameters=$parameters} | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $file -Encoding utf8NoBOM
    $operation = @{Validate='validate';WhatIf='what-if';Deploy='create'}[$Action]
    $arguments = @('deployment', 'group', $operation, '-g', $ResourceGroup, '--name', "candidate-$RevisionSuffix",
        '--template-file', (Join-Path $PSScriptRoot '..\infra\app.bicep'), '--parameters', "@$file", '-o', 'json')
    if ($Action -eq 'WhatIf') { $arguments += @('--no-pretty-print','--result-format','ResourceIdOnly') }
    $preview = Invoke-AzureCli $arguments
    if ($Action -eq 'WhatIf') {
        $changes = @($preview.changes)
        if (@($changes | Where-Object changeType -eq 'Delete').Count) { throw 'Candidate what-if contains deletions; no deployment permitted.' }
        Write-Output "What-if reviewed: $($changes.Count) resource changes, no deletions."
    }
} finally { Remove-Item -LiteralPath $file -Force }
if ($Action -ne 'Deploy') { Write-Output "Candidate $Action passed. Secret parameters were deleted; no application was deployed."; return }
$candidate = Invoke-AzureCli @('containerapp', 'revision', 'show', '-g', $ResourceGroup, '-n', $AppName,
    '--revision', $revision, '-o', 'json')
if (-not $candidate.properties.fqdn -or -not $candidate.properties.active -or
    $candidate.properties.template.containers[0].image -cne "$($registry.loginServer)/harness@$ImageDigest") {
    throw 'Candidate identity/image/activation could not be verified. No promotion was attempted.'
}
$state = @{
    subscriptionId=$SubscriptionId.ToString(); tenantId=$TenantId.ToString(); resourceGroup=$ResourceGroup
    appName=$AppName; candidateRevision=$revision; candidateImage="$($registry.loginServer)/harness@$ImageDigest"
    previousRevision=$stable; previousImage=$stableImage; smokeClientCidr=$SmokeClientCidr
    baseUri="https://$($candidate.properties.fqdn)/"; createdAtUtc=[DateTime]::UtcNow.ToString('O')
    authMode=$AuthMode
    mcpRequired=[bool]$RequireMcpSmoke
}
$null = New-Item -ItemType Directory -Path (Split-Path ([IO.Path]::GetFullPath($StatePath))) -Force
$state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $StatePath -Encoding utf8NoBOM
Write-Output "Candidate state saved at $StatePath. Smoke/promotion not executed."
if (-not $stable) { Write-Output 'Bootstrap has no earlier revision to roll back to.' }
else { Write-Output "Accepted predecessor $stable retains 100% traffic until fresh smoke/promotion." }

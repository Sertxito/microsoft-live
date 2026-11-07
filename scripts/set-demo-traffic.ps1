[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][guid] $SubscriptionId,
    [Parameter(Mandatory)][guid] $TenantId,
    [Parameter(Mandatory)][ValidateSet('Promote','Rollback')][string] $Action,
    [Parameter(Mandatory)][string] $StatePath,
    [string] $BearerToken,
    [string] $ForbiddenBearerToken,
    [string] $ApiKey,
    [switch] $AuthorizeAzureChanges,
    [switch] $AuthorizeRemoteSmoke
)
$ErrorActionPreference = 'Stop'
if (-not $AuthorizeAzureChanges) { throw 'Traffic changes require -AuthorizeAzureChanges.' }
if ($Action -eq 'Promote' -and (-not $AuthorizeRemoteSmoke -or
    (-not $ApiKey -and (-not $BearerToken -or -not $ForbiddenBearerToken)))) {
    throw 'Promotion requires explicit remote smoke authorization and valid permitted/forbidden tokens. Prior smoke files are not trusted.'
}
$StatePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($StatePath)
$state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
if ($state.subscriptionId -ne $SubscriptionId.ToString() -or $state.tenantId -ne $TenantId.ToString()) {
    throw 'Candidate state differs from the authorized subscription/tenant.'
}
if ($Action -eq 'Rollback' -and (-not $state.previousRevision -or -not $state.previousImage)) {
    throw 'Rollback requires a known previously accepted revision and image. No traffic changed.'
}
if (-not $PSCmdlet.ShouldProcess("$($state.resourceGroup) / $($state.appName)", "$Action explicitly named revision; preserve all revisions")) { return }
. (Join-Path $PSScriptRoot 'azure-common.ps1')
Assert-AzureContext $SubscriptionId $TenantId
Assert-DemoGroup $state.resourceGroup $SubscriptionId
function Get-CurrentApp {
    Invoke-AzureCli @('containerapp', 'show', '-g', $state.resourceGroup, '-n', $state.appName, '-o', 'json')
}
function Assert-UnchangedTraffic {
    param($App)
    if ($App.tags.project -ne 'microsoft-live' -or $App.properties.configuration.activeRevisionsMode -ne 'Multiple') {
        throw 'Target is not the isolated multi-revision demo.'
    }
    $expected = if ($Action -eq 'Rollback' -or -not $state.previousRevision) { $state.candidateRevision } else { $state.previousRevision }
    $traffic = @($App.properties.configuration.ingress.traffic | Where-Object weight -gt 0)
    if ($traffic.Count -ne 1 -or $traffic[0].revisionName -cne $expected -or $traffic[0].weight -ne 100) {
        throw 'Traffic changed since candidate creation; refusing to overwrite newer work.'
    }
}
Assert-UnchangedTraffic (Get-CurrentApp)
$target = if ($Action -eq 'Promote') { $state.candidateRevision } else { $state.previousRevision }
$image = if ($Action -eq 'Promote') { $state.candidateImage } else { $state.previousImage }
$revision = Invoke-AzureCli @('containerapp', 'revision', 'show', '-g', $state.resourceGroup, '-n', $state.appName,
    '--revision', $target, '-o', 'json')
if (-not $revision.properties.active -or $revision.properties.template.containers[0].image -cne $image) {
    throw 'Expected revision is inactive or its image differs; traffic unchanged.'
}
if ($Action -eq 'Promote') {
    $baseUri = "https://$($revision.properties.fqdn)/"
    if (-not $revision.properties.fqdn -or $baseUri -cne $state.baseUri) { throw 'Candidate endpoint differs from Azure revision metadata.' }
    $smoke = @{BaseUri=$baseUri;ExpectedRevision=$target;AuthorizeRemote=$true;PassThru=$true}
    if ($state.authMode -eq 'ApiKey') {
        if (-not $ApiKey -or $BearerToken) { throw 'Candidate requires API-key smoke, not a JWT fallback.' }
        $smoke.ApiKey=$ApiKey
    } else { $smoke.BearerToken=$BearerToken; $smoke.ForbiddenBearerToken=$ForbiddenBearerToken }
    $evidence = & (Join-Path $PSScriptRoot 'smoke-test.ps1') @smoke
    $negativeChecked = if ($state.authMode -eq 'ApiKey') {$evidence.wrongKeyChecked -eq $true} else {$evidence.forbiddenChecked -eq $true}
    if ($evidence.passed -ne $true -or -not $negativeChecked -or $evidence.revision -cne $target) {
        throw 'Current smoke did not prove the candidate. Traffic unchanged.'
    }
    if ($state.mcpRequired -eq $true) {
        $mcpParameters=@{BaseUri=$baseUri;AuthorizeRemote=$true;PassThru=$true}
        if ($state.authMode -eq 'ApiKey') { $mcpParameters.ApiKey=$ApiKey } else { $mcpParameters.BearerToken=$BearerToken }
        $mcpEvidence = & (Join-Path $PSScriptRoot 'smoke-mcp.ps1') @mcpParameters
        if ($mcpEvidence.passed -ne $true -or $mcpEvidence.tool -ne 'buscar_tutoriales') {
            throw 'MCP candidate verification failed. Traffic unchanged.'
        }
    }
}
Assert-UnchangedTraffic (Get-CurrentApp)
$null = Invoke-AzureCli @('containerapp', 'ingress', 'traffic', 'set', '-g', $state.resourceGroup,
    '-n', $state.appName, '--revision-weight', "$target=100", '-o', 'json')
$updated = Get-CurrentApp
$traffic = @($updated.properties.configuration.ingress.traffic | Where-Object weight -gt 0)
if ($traffic.Count -ne 1 -or $traffic[0].revisionName -cne $target -or $traffic[0].weight -ne 100) {
    throw 'Traffic command returned but the selected revision is not at 100%; inspect Azure immediately. No success is claimed.'
}
$recordPath = Join-Path (Split-Path ([IO.Path]::GetFullPath($StatePath))) "traffic-$($Action.ToLowerInvariant()).json"
@{action=$Action; revision=$target; image=$image; checkedAtUtc=[DateTime]::UtcNow.ToString('O'); smoke=$evidence; mcpSmoke=$mcpEvidence} |
    ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $recordPath -Encoding utf8NoBOM
Write-Output "$Action verified: $target at 100%. IP restrictions and previous revisions were preserved."

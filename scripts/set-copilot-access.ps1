[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][guid] $SubscriptionId,
    [Parameter(Mandatory)][guid] $TenantId,
    [string] $ResourceGroup = 'rg-microsoft-live-demo',
    [string] $AppName = 'ca-m365live-demo',
    [string] $ReceiptPath = (Join-Path $PSScriptRoot '..\.local\azure\copilot-access.json'),
    [ValidateSet('Preview','Apply')][string] $Action = 'Preview',
    [switch] $AuthorizeNetworkChanges
)
$ErrorActionPreference = 'Stop'
if ($Action -eq 'Apply' -and -not $AuthorizeNetworkChanges) { throw 'Adding regional connector access requires -AuthorizeNetworkChanges.' }
if (-not $PSCmdlet.ShouldProcess("$ResourceGroup / $AppName", "$Action Europe connector IP allow rules; preserve authentication and traffic")) { return }
. (Join-Path $PSScriptRoot 'azure-common.ps1')
Assert-AzureContext $SubscriptionId $TenantId
Assert-DemoGroup $ResourceGroup $SubscriptionId
$app = Invoke-AzureCli @('containerapp','show','-g',$ResourceGroup,'-n',$AppName,'-o','json')
$ingress = $app.properties.configuration.ingress
$envs = $app.properties.template.containers[0].env
if ($app.tags.project -ne 'microsoft-live' -or $ingress.allowInsecure -ne $false -or
    @($envs | Where-Object { $_.name -eq 'HARNESS_AUTH_MODE' -and $_.value -eq 'ApiKey' }).Count -ne 1 -or
    @($envs | Where-Object { $_.name -eq 'HARNESS_API_KEY' -and $_.secretRef -eq 'api-key' }).Count -ne 1) {
    throw 'Expected HTTPS API-key demo not found; network access was not changed.'
}
$tags = Invoke-AzureCli @('network','list-service-tags','--location','westeurope','-o','json')
$names = @('AzureConnectors.NorthEurope','AzureConnectors.WestEurope','PowerPlatformPlex.NorthEurope','PowerPlatformPlex.WestEurope')
$selected = @($tags.values | Where-Object { $_.name -in $names })
if ($selected.Count -ne 4) { throw 'All four official Europe service tags must be available.' }
$existing = @($ingress.ipSecurityRestrictions)
if ($existing.Count -eq 0 -or @($existing | Where-Object action -ne 'Allow').Count) { throw 'Expected existing allow-list is absent or mixed with deny rules.' }
$additional = @()
foreach ($tag in $selected) {
    $index = 0
    foreach ($prefix in ($tag.properties.addressPrefixes | Where-Object { $_ -notmatch ':' } | Sort-Object)) {
        $index++
        if ($prefix -notmatch '^\d+\.\d+\.\d+\.\d+/(?:[1-9]|[12][0-9]|3[0-2])$') { throw 'Unsafe/non-IPv4 prefix returned by service-tag discovery.' }
        if ($prefix -notin @($existing.ipAddressRange) -and $prefix -notin @($additional.ipAddressRange)) {
            $additional += @{
                name = "copilot-$($tag.name.Replace('.','-').ToLowerInvariant())-$index"
                ipAddressRange = $prefix; action = 'Allow'; description = "Official $($tag.name); shared Microsoft egress"
            }
        }
    }
}
$rules = @($existing) + @($additional)
Write-Output "Europe connector preview: $($additional.Count) new IPv4 allow rules, $($existing.Count) existing rules preserved. IPv6 skipped (Container Apps IP rules are IPv4)."
if ($Action -eq 'Preview') { return }
$beforeTraffic = $ingress.traffic | ConvertTo-Json -Depth 20 -Compress
$beforeImage = $app.properties.template.containers[0].image
$beforeRevision = $app.properties.latestRevisionName
$beforeTemplate = $app.properties.template | ConvertTo-Json -Depth 100 -Compress
$beforeIdentity = $app.identity | ConvertTo-Json -Depth 100 -Compress
$beforeConfiguration = $app.properties.configuration | Select-Object * -ExcludeProperty ingress | ConvertTo-Json -Depth 100 -Compress
$ingress.ipSecurityRestrictions = $rules
$url = "https://management.azure.com$($app.id)?api-version=2025-07-01"
if ($additional.Count -gt 0) {
    $null = Invoke-AzureJsonBody PATCH $url @{properties=@{configuration=@{ingress=$ingress}}}
}
$deadline = [DateTime]::UtcNow.AddMinutes(2)
do {
    $updated = Invoke-AzureCli @('containerapp','show','-g',$ResourceGroup,'-n',$AppName,'-o','json')
    if ($updated.properties.provisioningState -eq 'Succeeded') { break }
    if ($updated.properties.provisioningState -eq 'Failed' -or [DateTime]::UtcNow -ge $deadline) {
        throw 'Network operation did not settle successfully; inspect the existing app before another mutation.'
    }
    Start-Sleep -Seconds 3
} while ($true)
$actual = @($updated.properties.configuration.ingress.ipSecurityRestrictions)
$failures = @(
    if (@(Compare-Object @($rules.ipAddressRange | Sort-Object) @($actual.ipAddressRange | Sort-Object)).Count) { 'IP ranges' }
    if (@($actual | Where-Object action -ne 'Allow').Count) { 'allow actions' }
    if ($updated.properties.configuration.ingress.allowInsecure -ne $false) { 'HTTPS' }
    if (($updated.properties.configuration.ingress.traffic | ConvertTo-Json -Depth 20 -Compress) -cne $beforeTraffic) { 'traffic' }
    if ($updated.properties.template.containers[0].image -cne $beforeImage) { 'image' }
    if ($updated.properties.latestRevisionName -cne $beforeRevision) { 'revision' }
    if (($updated.properties.template | ConvertTo-Json -Depth 100 -Compress) -cne $beforeTemplate) { 'runtime template' }
    if (($updated.identity | ConvertTo-Json -Depth 100 -Compress) -cne $beforeIdentity) { 'identity' }
    if (($updated.properties.configuration | Select-Object * -ExcludeProperty ingress | ConvertTo-Json -Depth 100 -Compress) -cne $beforeConfiguration) { 'configuration' }
)
if ($failures.Count) {
    throw "Network verification failed for $($failures -join ', '); inspect the existing app immediately. No verified access receipt was saved."
}
@{
    subscriptionId=$SubscriptionId.ToString();tenantId=$TenantId.ToString();resourceGroup=$ResourceGroup;appName=$AppName
    geo='Europe';serviceTags=$names;verifiedAtUtc=[DateTime]::UtcNow.ToString('O')
    rules=$actual;revision=$beforeRevision;image=$beforeImage
} | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $ReceiptPath -Encoding utf8NoBOM
Write-Output 'Europe connector access verified. HTTPS, key authentication, existing access, traffic, image and revision preserved. Copilot Studio import still needs an actual connection test.'

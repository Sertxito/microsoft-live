[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][guid] $SubscriptionId,
    [Parameter(Mandatory)][guid] $TenantId,
    [Parameter(Mandatory)][ValidatePattern('^rg-[a-zA-Z0-9-]+$')][string] $ResourceGroup,
    [Parameter(Mandatory)][string] $Owner,
    [string] $EnvironmentName = 'm365live-demo',
    [ValidateSet('Validate','WhatIf','Deploy')][string] $Action = 'Validate',
    [switch] $AuthorizeAzureChanges,
    [switch] $AuthorizeRbacChanges,
    [switch] $AuthorizeRemoteValidation
)
$ErrorActionPreference = 'Stop'
if ($Action -eq 'Deploy' -and (-not $AuthorizeAzureChanges -or -not $AuthorizeRbacChanges)) {
    throw 'Foundation deployment requires -AuthorizeAzureChanges and -AuthorizeRbacChanges.'
}
if ($Action -ne 'Deploy' -and -not $AuthorizeRemoteValidation) { throw 'Remote validation requires -AuthorizeRemoteValidation.' }
if (-not $PSCmdlet.ShouldProcess("$SubscriptionId / $ResourceGroup", "$Action foundation in West Europe")) { return }
. (Join-Path $PSScriptRoot 'azure-common.ps1')
Assert-AzureContext $SubscriptionId $TenantId
$exists = Invoke-AzureCli @('group', 'exists', '-n', $ResourceGroup, '--subscription', $SubscriptionId.ToString(), '-o', 'json')
if (-not $exists) {
    if ($Action -ne 'Deploy') { throw 'Create the authorized isolated resource group before remote group validation.' }
    $null = Invoke-AzureCli @('group', 'create', '-n', $ResourceGroup, '-l', 'westeurope',
        '--tags', 'project=microsoft-live', 'purpose=isolated-demo', "owner=$Owner",
        '--subscription', $SubscriptionId.ToString(), '-o', 'json')
}
Assert-DemoGroup $ResourceGroup $SubscriptionId
$operation = @{Validate='validate'; WhatIf='what-if'; Deploy='create'}[$Action]
$arguments = @('deployment', 'group', $operation, '-g', $ResourceGroup, '--subscription', $SubscriptionId.ToString(),
    '--name', 'demo-foundation', '--template-file', (Join-Path $PSScriptRoot '..\infra\main.bicep'),
    '--parameters', "environmentName=$EnvironmentName", 'location=westeurope', "owner=$Owner", '-o', 'json')
if ($Action -eq 'WhatIf') { $arguments += @('--no-pretty-print','--result-format','ResourceIdOnly') }
$result = Invoke-AzureCli $arguments
if ($Action -eq 'Deploy') {
    $path = Join-Path $PSScriptRoot '..\.local\azure\foundation.json'
    $null = New-Item -ItemType Directory -Path (Split-Path $path) -Force
    $outputs = $result.properties.outputs | ConvertTo-Json -Depth 30 | ConvertFrom-Json -AsHashtable
    $outputs.subscriptionId = $SubscriptionId.ToString()
    $outputs.tenantId = $TenantId.ToString()
    $outputs.resourceGroup = $ResourceGroup
    $outputs | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $path -Encoding utf8NoBOM
    Write-Output "Foundation deployed; non-secret outputs saved at $path. No image, catalog or application was published."
} else { $result }

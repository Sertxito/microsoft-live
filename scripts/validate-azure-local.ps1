[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'azure-common.ps1')
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
foreach ($directory in @('scripts','tests\fixtures')) {
    foreach ($file in Get-ChildItem (Join-Path $root $directory) -Filter *.ps1) {
        $tokens = $null
        $parseErrors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw "PowerShell parse failed for $($file.Name): $($parseErrors[0].Message)" }
    }
}
function Get-ArmResources {
    param($Template)
    $collection = if ($Template.resources -is [array]) { $Template.resources } else { $Template.resources.PSObject.Properties.Value }
    foreach ($resource in $collection) {
        $resource
        if ($resource.properties.template) { Get-ArmResources $resource.properties.template }
    }
}
function Assert-Condition {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) "demo-bicep-$([guid]::NewGuid().ToString('N'))"
$null = New-Item -ItemType Directory -Path $temporary
try {
    foreach ($name in @('main','app')) {
        $path = Join-Path $temporary "$name.json"
        $null = Invoke-AzureCli @('bicep', 'build', '--file', (Join-Path $root "infra\$name.bicep"), '--outfile', $path) -Text
    }
    $foundation = Get-Content (Join-Path $temporary 'main.json') -Raw | ConvertFrom-Json -Depth 100
    $application = Get-Content (Join-Path $temporary 'app.json') -Raw | ConvertFrom-Json -Depth 100
    $resources = @(Get-ArmResources $foundation)
    $search = @($resources | Where-Object type -eq 'Microsoft.Search/searchServices')
    Assert-Condition ($search.Count -eq 1 -and $search[0].properties.disableLocalAuth -eq $true -and
        $null -eq $search[0].properties.authOptions) 'Search must use Entra only, without incompatible authOptions.'
    $storage = @($resources | Where-Object type -eq 'Microsoft.Storage/storageAccounts')
    Assert-Condition ($storage.Count -eq 1 -and $storage[0].properties.allowSharedKeyAccess -eq $false -and
        $storage[0].properties.allowBlobPublicAccess -eq $false -and $storage[0].properties.supportsHttpsTrafficOnly -eq $true) 'Storage must forbid keys and public blobs and require HTTPS.'
    $registry = @($resources | Where-Object type -eq 'Microsoft.ContainerRegistry/registries')
    Assert-Condition ($registry.Count -eq 1 -and $registry[0].properties.adminUserEnabled -eq $false) 'Registry admin must be disabled.'
    $roles = @($resources | Where-Object type -eq 'Microsoft.Authorization/roleAssignments')
    Assert-Condition ($roles.Count -eq 4 -and @($roles | Where-Object { -not $_.scope }).Count -eq 0) 'All RBAC assignments must have an explicit resource scope (one assignment loops over two loader roles).'
    $apps = @(Get-ArmResources $application | Where-Object type -eq 'Microsoft.App/containerApps')
    Assert-Condition ($apps.Count -eq 1) 'Expected exactly one application.'
    $app = $apps[0]
    $ingressRules = $app.properties.configuration.ingress.ipSecurityRestrictions
    Assert-Condition ($app.properties.configuration.activeRevisionsMode -eq 'Multiple' -and
        $app.properties.configuration.ingress.allowInsecure -eq $false -and
        $app.properties.configuration.ingress.traffic[0].weight -eq 100 -and
        $ingressRules -is [string] -and
        $ingressRules.Contains("'ipAddressRange', parameters('smokeClientCidr'), 'action', 'Allow'") -and
        $ingressRules.EndsWith(", parameters('connectorIngressRules'))]") -and
        $application.parameters.connectorIngressRules.defaultValue.Count -eq 0) 'App must preserve named revision traffic, the operator allow rule and explicitly supplied connector access.'
    Assert-Condition ($app.properties.template.scale.minReplicas -eq 0 -and
        $app.properties.template.scale.maxReplicas -eq 1) 'Demo scale must be bounded to zero through one replicas.'
    $probes = $app.properties.template.containers[0].probes
    Assert-Condition (@($probes | Where-Object { $_.httpGet.path -eq '/health/ready' }).Count -eq 0) 'Protected readiness must not be used by anonymous platform probes.'
    foreach ($name in @('imageDigest','smokeClientCidr','revisionSuffix')) {
        Assert-Condition ($null -eq $application.parameters.$name.defaultValue) "Application parameter $name must be supplied explicitly."
    }
    Assert-Condition ($application.parameters.apiKey.type -eq 'secureString' -and
        $application.parameters.apiKey.defaultValue -eq '' -and $application.parameters.authMode.defaultValue -eq 'Jwt') 'API key must be secure, opt-in and never configured as a default secret.'
    $docker = Get-Content (Join-Path $root 'src\Harness.Api\Dockerfile') -Raw
    Assert-Condition (([regex]::Matches($docker, 'mcr\.microsoft\.com/dotnet/(sdk|aspnet):[0-9.]+@sha256:[a-f0-9]{64}')).Count -eq 2) 'Both .NET base images must be pinned by digest.'
    $schema = Get-Content (Join-Path $root 'infra\search-index.json') -Raw | ConvertFrom-Json
    $catalog = @(Get-Content (Join-Path $root 'knowledge\tutorials\catalog.json') -Raw | ConvertFrom-Json)
    foreach ($document in $catalog) {
        Assert-Condition (@(Compare-Object @($schema.fields.name) @($document.PSObject.Properties.Name)).Count -eq 0) 'Search schema must match every catalog document.'
    }
    $null = Get-Content (Join-Path $root 'infra\main.parameters.json') -Raw | ConvertFrom-Json
    Write-Output 'Local Azure preparation checks passed: PowerShell syntax, two Bicep compilations, ARM safety invariants, image pins and catalog schema. No Azure resource or Docker build was contacted.'
} finally {
    Remove-Item -LiteralPath $temporary -Recurse -Force
}

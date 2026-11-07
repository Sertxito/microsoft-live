[CmdletBinding()]
param(
    [ValidateSet('LocalDeterministic', 'AzureIntegrated')]
    [string] $Mode = 'LocalDeterministic'
)

$ErrorActionPreference = 'Stop'
$checks = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param([string] $Name, [bool] $Available, [string] $Detail)
    $script:checks.Add([pscustomobject]@{
        requirement = $Name
        available = $Available
        detail = $Detail
    })
}

$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
Add-Check 'dotnet-sdk' ($null -ne $dotnet) $(if ($dotnet) { 'Installed executable found; SDK version is pinned by global.json.' } else { 'dotnet was not found on PATH.' })
if ($dotnet) {
    Push-Location (Split-Path $PSScriptRoot -Parent)
    try {
        $sdk = & dotnet --version
        $sdkReady = $LASTEXITCODE -eq 0 -and $sdk -eq '10.0.401'
        Add-Check 'pinned-sdk' $sdkReady $(if ($sdkReady) { "Selected SDK: $sdk." } else { 'The pinned SDK is unavailable; no installation was attempted.' })
    } finally { Pop-Location }
}

$catalog = Join-Path $PSScriptRoot '..\knowledge\tutorials\catalog.json'
Add-Check 'synthetic-tutorial-catalog' (Test-Path -LiteralPath $catalog -PathType Leaf) $(if (Test-Path -LiteralPath $catalog -PathType Leaf) { 'Local synthetic catalog is present.' } else { 'Catalog file is missing.' })

if ($Mode -eq 'LocalDeterministic') {
    $ready = @($checks | Where-Object { -not $_.available }).Count -eq 0
    [pscustomobject]@{
        mode = $Mode
        ready = $ready
        requirements = $checks
        note = 'This mode does not require Azure, Docker, credentials, or a model.'
    } | ConvertTo-Json -Depth 4
    if (-not $ready) { exit 1 }
    exit 0
}

$azureCli = Get-Command az -ErrorAction SilentlyContinue
Add-Check 'azure-cli' ($null -ne $azureCli) $(if ($azureCli) { 'Azure CLI executable found; account and service readiness were not queried.' } else { 'Azure CLI was not found on PATH.' })
Add-Check 'container-build-strategy' $true 'An explicit ACR cloud-build script is prepared; local Docker is optional. No source upload or build was performed.'
Add-Check 'azure-integrated-adapter' $true 'Azure Search adapter is implemented and tested with an in-memory transport, not validated against Azure.'
foreach ($name in @('HARNESS_AUTHORITY', 'HARNESS_AUTH_AUDIENCE', 'HARNESS_SEARCH_ENDPOINT', 'HARNESS_SEARCH_INDEX', 'HARNESS_SEARCH_MINIMUM_SCORE', 'HARNESS_MANAGED_IDENTITY_CLIENT_ID')) {
    $present = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))
    Add-Check $name $present $(if ($present) { 'Value provided; remote validity was not checked.' } else { 'Required configuration is missing.' })
}
Add-Check 'remote-readiness' $false 'Tenant, RBAC, index, runtime patch support and deployment require separately authorized verification.'

[pscustomobject]@{
    mode = $Mode
    ready = $false
    requirements = $checks
    note = 'AzureIntegrated is not ready. This check does not query Azure, inspect credential values, or install tools.'
} | ConvertTo-Json -Depth 4
exit 1

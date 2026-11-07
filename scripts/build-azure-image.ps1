[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][guid] $SubscriptionId,
    [Parameter(Mandatory)][guid] $TenantId,
    [Parameter(Mandatory)][string] $ResourceGroup,
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9]{5,50}$')][string] $RegistryName,
    [switch] $AuthorizeSourceUpload
)
$ErrorActionPreference = 'Stop'
if (-not $AuthorizeSourceUpload) { throw 'ACR cloud build uploads source and incurs usage: require -AuthorizeSourceUpload.' }
if (-not $PSCmdlet.ShouldProcess("$ResourceGroup / $RegistryName", 'Upload allowlisted source and build immutable demo image with ACR')) { return }
. (Join-Path $PSScriptRoot 'azure-common.ps1')
Assert-AzureContext $SubscriptionId $TenantId
Assert-DemoGroup $ResourceGroup $SubscriptionId
$registry = Invoke-AzureCli @('acr', 'show', '-g', $ResourceGroup, '-n', $RegistryName, '-o', 'json')
if ($registry.tags.project -ne 'microsoft-live') { throw 'Registry is not a demo resource.' }
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$stage = Join-Path ([IO.Path]::GetTempPath()) "microsoft-live-build-$([guid]::NewGuid().ToString('N'))"
$null = New-Item -ItemType Directory -Path $stage
try {
    foreach ($name in @('global.json','Directory.Build.props','.dockerignore','knowledge\tutorials\catalog.json')) {
        $target = Join-Path $stage $name
        $null = New-Item -ItemType Directory -Path (Split-Path $target) -Force
        Copy-Item -LiteralPath (Join-Path $root $name) -Destination $target
    }
    $files = Get-ChildItem (Join-Path $root 'src') -File -Recurse |
        Where-Object { $_.FullName -notmatch '[\\/](bin|obj)[\\/]' -and
            ($_.Extension -in @('.cs','.csproj') -or $_.Name -in @('Dockerfile','openapi.json')) }
    foreach ($file in $files) {
        if ($file.LinkType) { throw 'Build allowlist contains a symbolic link; refusing transfer.' }
        $target = Join-Path $stage ([IO.Path]::GetRelativePath($root, $file.FullName))
        $null = New-Item -ItemType Directory -Path (Split-Path $target) -Force
        Copy-Item -LiteralPath $file.FullName -Destination $target
    }
    $tag = "demo-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    $null = Invoke-AzureCli @('acr', 'build', '-r', $RegistryName, '-g', $ResourceGroup,
        '--image', "harness:$tag", '--file', 'src\Harness.Api\Dockerfile', '--platform', 'linux/amd64', '--no-logs', $stage, '-o', 'json')
    $image = Invoke-AzureCli @('acr', 'repository', 'show', '-n', $RegistryName, '--image', "harness:$tag", '-o', 'json')
    if ($image.digest -notmatch '^sha256:[a-f0-9]{64}$') { throw 'Registry did not return a valid immutable image digest.' }
    Write-Output "$($registry.loginServer)/harness@$($image.digest)"
} finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}

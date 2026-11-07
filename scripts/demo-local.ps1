[CmdletBinding()]
param([string] $Query)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    $project = Join-Path $root 'tests\Harness.LocalDemo\Harness.LocalDemo.csproj'
    if ($Query) {
        & dotnet run --no-build --project $project -- $Query
    } else {
        & dotnet run --no-build --project $project
    }
    if ($LASTEXITCODE -ne 0) { throw "Local demo failed (exit $LASTEXITCODE)." }
} finally {
    Pop-Location
}

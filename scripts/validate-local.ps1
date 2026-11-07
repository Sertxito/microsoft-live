[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'setup-check.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Local prerequisites are incomplete.' }
    & dotnet build Harness.sln --no-restore
    if ($LASTEXITCODE -ne 0) { throw 'Build failed; dependencies must be restored separately with approval.' }
    & dotnet test Harness.sln --no-build --logger 'trx' --results-directory (Join-Path $root 'TestResults')
    if ($LASTEXITCODE -ne 0) { throw 'Local validation failed.' }
} finally {
    Pop-Location
}

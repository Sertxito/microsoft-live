[CmdletBinding()]
param([Parameter(Mandatory)][string] $Destination)
$ErrorActionPreference = 'Stop'
if (-not [IO.Path]::IsPathFullyQualified($Destination)) { throw 'Destination must be an explicit absolute local path.' }
if ($Destination.StartsWith('\\')) { throw 'Network destinations require separate transfer authorization.' }
$root = Split-Path $PSScriptRoot -Parent
& dotnet run --no-build --project (Join-Path $root 'src\Harness.Api\Harness.Api.csproj') -- seed $Destination
if ($LASTEXITCODE -ne 0) { throw "Local seeding failed (exit $LASTEXITCODE)." }

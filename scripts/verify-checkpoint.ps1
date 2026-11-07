[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Manifest
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$record = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
if ($record.tag -notmatch '^[A-Za-z0-9][A-Za-z0-9._/-]*$' -or $record.commit -notmatch '^[a-f0-9]{40}$') {
    throw 'Checkpoint needs a valid Git tag and exact commit.'
}
$commit = & git -C $root rev-parse --verify --quiet "refs/tags/$($record.tag)^{commit}" 2>$null
if ($LASTEXITCODE -ne 0 -or $commit -ne $record.commit) { throw 'Checkpoint tag is absent or does not resolve to the expected commit.' }
if (@($record.files).Count -eq 0) { throw 'Checkpoint file inventory is empty.' }
foreach ($file in $record.files) {
    if ($file.path -notmatch '^[A-Za-z0-9_./-]+$' -or $file.path -match '(^|/)\.\.(/|$)' -or $file.sha256 -notmatch '^[a-f0-9]{64}$') {
        throw 'Invalid checkpoint file entry.'
    }
    $path = [IO.Path]::GetFullPath((Join-Path $root $file.path))
    if (-not $path.StartsWith("$root$([IO.Path]::DirectorySeparatorChar)", [StringComparison]::OrdinalIgnoreCase)) { throw 'Checkpoint path escapes repository.' }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing checkpoint file: $($file.path)." }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256) { throw "Checksum mismatch: $($file.path)." }
}
Write-Output 'Checkpoint tag, commit and current local checksums match. Nothing was restored.'

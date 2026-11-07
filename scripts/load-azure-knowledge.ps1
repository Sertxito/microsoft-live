[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][guid] $SubscriptionId,
    [Parameter(Mandatory)][guid] $TenantId,
    [Parameter(Mandatory)][string] $ResourceGroup,
    [Parameter(Mandatory)][guid] $ExpectedLoaderPrincipalId,
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9][a-z0-9-]{1,58}[a-z0-9]$')][string] $SearchName,
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9]{3,24}$')][string] $StorageName,
    [ValidatePattern('^[a-z][a-z0-9-]{1,126}$')][string] $IndexName = 'tutorials',
    [string] $FoundationPath = (Join-Path $PSScriptRoot '..\.local\azure\foundation.json'),
    [switch] $AuthorizeDataUpload
)
$ErrorActionPreference = 'Stop'
if (-not $AuthorizeDataUpload) { throw 'Catalog/Blob transfer and index creation require -AuthorizeDataUpload.' }
if (-not $PSCmdlet.ShouldProcess("$ResourceGroup / $SearchName / $StorageName", 'Upload synthetic catalog and merge documents using the explicitly selected loader identity')) { return }
. (Join-Path $PSScriptRoot 'azure-common.ps1')
Assert-AzureContext $SubscriptionId $TenantId
$foundation = Get-Content -LiteralPath $FoundationPath -Raw | ConvertFrom-Json
if ($foundation.subscriptionId -ne $SubscriptionId.ToString() -or $foundation.tenantId -ne $TenantId.ToString() -or
    $foundation.resourceGroup -ne $ResourceGroup -or $foundation.searchName.value -ne $SearchName -or
    $foundation.storageName.value -ne $StorageName) {
    throw 'Upload destinations differ from the locally recorded authorized foundation.'
}

$token = Invoke-AzureCli @('account', 'get-access-token', '--resource', 'https://search.azure.com', '-o', 'json')
$encoded = $token.accessToken.Split('.')[1].Replace('-', '+').Replace('_', '/')
$encoded = $encoded.PadRight($encoded.Length + ((4 - $encoded.Length % 4) % 4), '=')
$claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded)) | ConvertFrom-Json
if ($claims.oid -ne $ExpectedLoaderPrincipalId.ToString() -or $claims.tid -ne $TenantId.ToString()) {
    throw 'Signed-in CLI identity differs from the specifically authorized loader principal.'
}
$token = $null
$catalogPath = Join-Path $PSScriptRoot '..\knowledge\tutorials\catalog.json'
$documents = @(Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json -Depth 20)
if ($documents.Count -lt 12 -or $documents.Count -gt 20 -or
    @($documents.id | Sort-Object -Unique).Count -ne $documents.Count) {
    throw 'Catalog must contain 12-20 uniquely identified synthetic tutorials.'
}
$schema = Get-Content (Join-Path $PSScriptRoot '..\infra\search-index.json') -Raw | ConvertFrom-Json -Depth 30
$schema.name = $IndexName
$required = @($schema.fields.name)
foreach ($document in $documents) {
    if (@($document.PSObject.Properties.Name | Where-Object { $_ -notin $required }).Count -ne 0 -or
        @($required | Where-Object { $_ -notin $document.PSObject.Properties.Name }).Count -ne 0 -or
        $document.id -notmatch '^tutorial-[0-9]{3}$' -or
        $document.status -notin @('active','inactive') -or $document.audience -notin @('community','operations') -or
        $document.sourceUrl -notmatch '^https://example\.invalid/tutorials/tutorial-[0-9]{3}$' -or
        $document.version -lt 1 -or -not $document.title -or -not $document.content) {
        throw 'Only the reviewed synthetic tutorial catalog schema may be uploaded.'
    }
}
$endpoint = "https://$SearchName.search.windows.net"
$resource = 'https://search.azure.com'
$indexes = Invoke-AzureCli @('rest', '--method', 'GET', '--url', "$endpoint/indexes?api-version=2024-07-01",
    '--resource', $resource, '-o', 'json')
$existing = @($indexes.value | Where-Object name -eq $IndexName)
if ($existing.Count -gt 1) { throw 'Ambiguous index definition.' }
if ($existing.Count -eq 1) {
    foreach ($field in $schema.fields) {
        $actual = @($existing[0].fields | Where-Object name -eq $field.name)
        if ($actual.Count -ne 1 -or $actual[0].type -ne $field.type -or
            [bool]$actual[0].key -ne [bool]$field.key -or [bool]$actual[0].filterable -ne [bool]$field.filterable -or
            [bool]$actual[0].searchable -ne [bool]$field.searchable -or
            $actual[0].analyzer -ne $field.analyzer) { throw 'Existing index schema differs; review migration separately. Nothing was uploaded.' }
    }
    $current = Invoke-AzureJsonBody POST "$endpoint/indexes/$IndexName/docs/search?api-version=2024-07-01" @{
        search='*'; select='id'; top=1000; count=$true
    } $resource
    $ids = @(@($current.value.id) + @($documents.id) | Sort-Object -Unique)
    if ($current.'@odata.count' -gt 20 -or $ids.Count -gt 20) { throw 'Merged catalog would exceed the 20-document demo limit.' }
} else {
    $null = Invoke-AzureJsonBody PUT "$endpoint/indexes/$IndexName`?api-version=2024-07-01" $schema $resource
}
$null = Invoke-AzureCli @('storage', 'blob', 'upload', '--account-name', $StorageName,
    '--container-name', 'tutorials', '--name', 'catalog.json', '--file', $catalogPath,
    '--auth-mode', 'login', '--overwrite', 'true', '-o', 'json')
$batch = @($documents | ForEach-Object {
    $record = $_ | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable
    $record['@search.action'] = 'mergeOrUpload'
    $record
})
$result = Invoke-AzureJsonBody POST "$endpoint/indexes/$IndexName/docs/index?api-version=2024-07-01" @{value=$batch} $resource
if (@($result.value).Count -ne $documents.Count -or @($result.value | Where-Object { $_.status -ne $true }).Count -ne 0) {
    throw 'Azure Search reported an incomplete document batch. Inspect the index before retrying; no success is claimed.'
}
Write-Output "Blob catalog uploaded and $($documents.Count) documents merged. No deletions, keys, fallback or runtime write rights were used."

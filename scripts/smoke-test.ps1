[CmdletBinding()]
param(
    [Parameter(Mandatory)][uri] $BaseUri,
    [string] $BearerToken,
    [string] $ApiKey,
    [string] $ForbiddenBearerToken,
    [string] $ExpectedRevision,
    [switch] $PassThru,
    [switch] $AuthorizeRemote
)
$ErrorActionPreference = 'Stop'
if ($BaseUri.Scheme -ne 'https' -or $BaseUri.UserInfo -or $BaseUri.Query -or $BaseUri.Fragment -or $BaseUri.AbsolutePath -ne '/') {
    throw 'Provide a root HTTPS service URI without credentials, query or fragment.'
}
if (-not $AuthorizeRemote) { throw 'Remote calls require explicit target authorization: -AuthorizeRemote.' }
if (([bool]$ApiKey) -eq ([bool]$BearerToken)) { throw 'Supply exactly one API key or bearer token for the selected deployment mode.' }
$base = $BaseUri.AbsoluteUri.TrimEnd('/')
$headers = @{ Authorization = "Bearer $BearerToken" }
if ($ApiKey) { $headers = @{ 'X-API-Key' = $ApiKey } }
function Assert-Status {
    param([string] $Path, [int] $Expected, [hashtable] $Headers = @{}, [string] $Body)
    $options = @{ Uri = "$base$Path"; Headers = $Headers; SkipHttpErrorCheck = $true; TimeoutSec = 15; MaximumRedirection = 0 }
    if ($Body) { $options.Method = 'Post'; $options.Body = $Body; $options.ContentType = 'application/json' }
    try { $response = Invoke-WebRequest @options } catch { throw "Smoke request failed for $Path; inspect the target without logging credentials." }
    if ([int]$response.StatusCode -ne $Expected) { throw "Smoke failed for $Path; expected $Expected, got $($response.StatusCode)." }
    if (-not $response.Headers['X-Correlation-ID']) { throw "Missing correlation header for $Path." }
    $value = $response.Content | ConvertFrom-Json
    if (($Expected -ge 400 -or $value.PSObject.Properties.Name -contains 'correlationId') -and
        $value.correlationId -cne ($response.Headers['X-Correlation-ID'] -join '')) {
        throw "Uncorrelated response for $Path."
    }
    return $value
}
$live = Assert-Status '/health/live' 200
if (@($live.PSObject.Properties).Count -ne 1 -or $live.status -ne 'live') { throw 'Liveness leaked details or is invalid.' }
$null = Assert-Status '/health/ready' 401
$null = Assert-Status '/api/capabilities' 401
$null = Assert-Status '/health/ready' 200 $headers
$capabilities = Assert-Status '/api/capabilities' 200 $headers
if ($ExpectedRevision -and ($capabilities.revision -cne $ExpectedRevision -or $capabilities.mode -ne 'AzureIntegrated')) {
    throw 'Smoke reached a different revision or a non-Azure provider; promotion is forbidden.'
}
if ($ForbiddenBearerToken) {
    $forbiddenHeaders = @{ Authorization = "Bearer $ForbiddenBearerToken" }
    $null = Assert-Status '/api/tutorials/search' 403 $forbiddenHeaders '{"query":"azure"}'
}
if ($ApiKey) {
    if ($capabilities.authMode -ne 'ApiKey') { throw 'Smoke reached a deployment with a different authentication mode.' }
    $null = Assert-Status '/api/tutorials/search' 401 @{ 'X-API-Key' = 'invalid-key' } '{"query":"azure"}'
}
$null = Assert-Status '/api/tutorials/search' 401 @{} '{"query":"azure"}'
$null = Assert-Status '/api/tutorials/search' 400 $headers '{"query":"ab"}'
$result = Assert-Status '/api/tutorials/search' 200 $headers '{"query":"azure","maxResults":5,"audience":"community"}'
if ($result.PSObject.Properties.Name -notcontains 'generatedAnswer' -or
    $null -ne $result.generatedAnswer -or $result.results.Count -lt 1 -or $result.results.Count -gt 5) {
    throw 'Invalid or empty retrieval contract; verify the uploaded Azure catalog.'
}
foreach ($hit in $result.results) {
    if ($hit.source -notmatch '^https?://') { throw 'A result lacks a supported source URI.' }
}
if ($PassThru) {
    [pscustomobject]@{
        passed = $true; revision = $capabilities.revision; mode = $capabilities.mode
        baseUri = $BaseUri.AbsoluteUri; checkedAtUtc = [DateTime]::UtcNow.ToString('O')
        forbiddenChecked = [bool]$ForbiddenBearerToken
        authMode = $(if ($ApiKey) {'ApiKey'} else {'Jwt'})
        wrongKeyChecked = [bool]$ApiKey
    }
} else { Write-Output 'Remote smoke passed for the explicitly authorized destination. No traffic promotion was performed.' }

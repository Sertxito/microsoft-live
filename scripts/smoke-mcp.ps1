[CmdletBinding()]
param(
    [Parameter(Mandatory)][uri] $BaseUri,
    [string] $ApiKey,
    [string] $BearerToken,
    [switch] $AuthorizeRemote,
    [switch] $PassThru
)
$ErrorActionPreference = 'Stop'
if (-not $AuthorizeRemote) { throw 'MCP remote calls require -AuthorizeRemote.' }
if ($BaseUri.Scheme -ne 'https' -or $BaseUri.UserInfo -or $BaseUri.Query -or $BaseUri.Fragment -or $BaseUri.AbsolutePath -ne '/') {
    throw 'MCP smoke requires a root HTTPS URI without credentials, query or fragment.'
}
if (([bool]$ApiKey) -eq ([bool]$BearerToken)) { throw 'Supply exactly one selected authentication credential; no anonymous fallback.' }
$uri = "$($BaseUri.AbsoluteUri.TrimEnd('/'))/mcp"
$headers = @{Accept='application/json, text/event-stream';'MCP-Protocol-Version'='2025-03-26'}
if ($ApiKey) { $headers['X-API-Key']=$ApiKey } else { $headers.Authorization="Bearer $BearerToken" }
function Invoke-McpRequest {
    param([string] $Method, [hashtable] $Parameters, [hashtable] $AuthHeaders, [int] $ExpectedStatus = 200, [int] $Id = 1)
    $body=@{jsonrpc='2.0';id=$Id;method=$Method;params=$Parameters} | ConvertTo-Json -Depth 20 -Compress
    try {
        $response=Invoke-WebRequest -Uri $uri -Method Post -Headers $AuthHeaders -Body $body `
            -ContentType 'application/json' -SkipHttpErrorCheck -TimeoutSec 30 -MaximumRedirection 0
    } catch {
        $detail=$_.Exception.GetType().Name
        if ($_.Exception -is [Management.Automation.ParameterBindingException]) { $detail += ": $($_.Exception.ParameterName)" }
        throw "MCP $Method transport failed ($detail); inspect the selected endpoint without logging credentials."
    }
    if ([int]$response.StatusCode -ne $ExpectedStatus) { throw "MCP $Method expected HTTP $ExpectedStatus, got $($response.StatusCode)." }
    if ($ExpectedStatus -ne 200) { return }
    $content=$response.Content
    if (($response.Headers['Content-Type'] -join '') -like 'text/event-stream*') {
        $messages=@($content -split '\r?\n' | Where-Object { $_.StartsWith('data:') } |
            ForEach-Object { $_.Substring(5).Trim() | ConvertFrom-Json -Depth 30 })
        $message=@($messages | Where-Object { $_.id -eq $Id })
        if ($message.Count -ne 1) { throw "MCP $Method returned an unexpected SSE response shape." }
        $value=$message[0]
    } else { $value=$content | ConvertFrom-Json -Depth 30 }
    if ($value.jsonrpc -ne '2.0' -or $value.id -ne $Id -or $value.error -or -not $value.result) {
        throw "MCP $Method did not return the expected JSON-RPC result."
    }
    return $value.result
}
$anonymous=@{Accept=$headers.Accept;'MCP-Protocol-Version'=$headers['MCP-Protocol-Version']}
$null=Invoke-McpRequest 'tools/list' @{} $anonymous 401
if ($ApiKey) {
    $wrong=$anonymous.Clone();$wrong['X-API-Key']='invalid-key'
    $null=Invoke-McpRequest 'tools/list' @{} $wrong 401
}
$initialize=Invoke-McpRequest 'initialize' @{
    protocolVersion='2025-03-26';capabilities=@{};clientInfo=@{name='harness-mcp-smoke';version='1.0'}
} $headers
if ($initialize.protocolVersion -ne '2025-03-26' -or $null -eq $initialize.capabilities.tools) {
    throw 'MCP initialization did not negotiate the requested tool protocol.'
}
try {
    $notification=Invoke-WebRequest -Uri $uri -Method Post -Headers $headers `
        -Body '{"jsonrpc":"2.0","method":"notifications/initialized"}' -ContentType 'application/json' `
        -SkipHttpErrorCheck -TimeoutSec 30 -MaximumRedirection 0
} catch { throw 'MCP initialized notification transport failed; credentials were not logged.' }
if ([int]$notification.StatusCode -ne 202) { throw "MCP initialized notification expected HTTP 202, got $($notification.StatusCode)." }
$tools=Invoke-McpRequest 'tools/list' @{} $headers
if (@($tools.tools).Count -ne 1 -or $tools.tools[0].name -ne 'buscar_tutoriales' -or
    @($tools.tools[0].inputSchema.required).Count -ne 1 -or $tools.tools[0].inputSchema.required[0] -ne 'query') {
    throw 'MCP discovery did not expose exactly the supported search tool.'
}
$result=Invoke-McpRequest 'tools/call' @{name='buscar_tutoriales';arguments=@{query='container apps';maxResults=1;audience='community'}} $headers
$data=$result.structuredContent
if ($result.isError -eq $true) {
    $safeCode=if ($data.code -in @('validation_error','request_timeout','search_unavailable','invalid_search_response','internal_error')) {$data.code} else {'unavailable'}
    throw "MCP search tool reported an error (code $safeCode); no success or traffic change is claimed."
}
if (-not $data -or
    $data.PSObject.Properties.Name -notcontains 'generatedAnswer' -or $null -ne $data.generatedAnswer -or
    @($data.results).Count -ne 1 -or $data.results[0].id -ne 'tutorial-001' -or
    $data.results[0].source -notmatch '^https?://' -or -not $data.correlationId) {
    throw 'MCP search did not return the supported retrieval-only structured content.'
}
$invalid=Invoke-McpRequest 'tools/call' @{name='buscar_tutoriales';arguments=@{query='ab'}} $headers
if ($invalid.isError -ne $true -or $invalid.structuredContent.code -ne 'validation_error') {
    throw 'MCP invalid arguments were not surfaced as a tool error.'
}
$evidence=@{
    passed=$true;endpoint=$uri;protocolVersion=$initialize.protocolVersion;tool='buscar_tutoriales'
    correlationId=$data.correlationId;checkedAtUtc=[DateTime]::UtcNow.ToString('O')
    anonymousRejected=$true;wrongKeyChecked=[bool]$ApiKey;invalidArgumentsRejected=$true
}
if ($PassThru) { [pscustomobject]$evidence } else { Write-Output 'MCP initialize, discovery, search and negative checks passed; no traffic change was performed.' }

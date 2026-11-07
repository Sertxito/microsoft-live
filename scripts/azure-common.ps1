$ErrorActionPreference = 'Stop'
$env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL = 'no'
$env:AZURE_BICEP_CHECK_VERSION = 'false'

function Invoke-AzureCli {
    param([Parameter(Mandatory)][string[]] $Arguments, [switch] $Text)
    $errorFile = [IO.Path]::GetTempFileName()
    try {
        $result = & az @Arguments --only-show-errors 2> $errorFile
        if ($LASTEXITCODE -ne 0) {
            $details = Get-Content -LiteralPath $errorFile -Raw
            $code = [regex]::Match($details, '"code"\s*:\s*"([A-Za-z0-9_.-]+)"')
            $safeCode = if ($code.Success) { $code.Groups[1].Value } else { 'unavailable' }
            throw "Azure CLI operation '$($Arguments[0])' failed (exit $LASTEXITCODE; code $safeCode). Inspect permissions and deployment status; credentials and request bodies are not printed."
        }
        $raw = $result -join "`n"
        if ($Text) { return $raw }
        if (-not [string]::IsNullOrWhiteSpace($raw)) { return ($raw | ConvertFrom-Json -Depth 100) }
    } finally { Remove-Item -LiteralPath $errorFile -Force }
}

function Assert-AzureContext {
    param([Parameter(Mandatory)][guid] $SubscriptionId, [Parameter(Mandatory)][guid] $TenantId)
    $account = Invoke-AzureCli @('account', 'show', '-o', 'json')
    if ($account.id -ne $SubscriptionId.ToString() -or $account.tenantId -ne $TenantId.ToString() -or
        $account.state -ne 'Enabled') {
        throw 'Azure CLI current subscription/tenant differs from the authorized target, or is disabled. Select it explicitly outside this script.'
    }
}

function Assert-DemoGroup {
    param([Parameter(Mandatory)][string] $ResourceGroup, [Parameter(Mandatory)][guid] $SubscriptionId)
    $group = Invoke-AzureCli @('group', 'show', '-n', $ResourceGroup, '--subscription', $SubscriptionId.ToString(), '-o', 'json')
    if ($group.tags.project -ne 'microsoft-live' -or $group.tags.purpose -ne 'isolated-demo' -or
        $group.location -ne 'westeurope') {
        throw 'Resource group is not an explicitly isolated microsoft-live demo in West Europe.'
    }
}

function Invoke-AzureJsonBody {
    param([Parameter(Mandatory)][string] $Method, [Parameter(Mandatory)][string] $Url,
        [Parameter(Mandatory)] $Body, [string] $Resource)
    $file = [IO.Path]::GetTempFileName()
    try {
        $Body | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $file -Encoding utf8NoBOM
        $arguments = @('rest', '--method', $Method, '--url', $Url, '--body', "@$file",
            '--headers', 'Content-Type=application/json', '-o', 'json')
        if ($Resource) { $arguments += @('--resource', $Resource) }
        Invoke-AzureCli $arguments
    } finally { Remove-Item -LiteralPath $file -Force }
}

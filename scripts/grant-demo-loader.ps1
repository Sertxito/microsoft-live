[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][guid] $SubscriptionId,
    [Parameter(Mandatory)][guid] $TenantId,
    [Parameter(Mandatory)][string] $ResourceGroup,
    [Parameter(Mandatory)][guid] $PrincipalId,
    [Parameter(Mandatory)][ValidateSet('User','ServicePrincipal')][string] $PrincipalType,
    [Parameter(Mandatory)][string] $SearchName,
    [Parameter(Mandatory)][string] $StorageName,
    [switch] $AuthorizeRbacChanges
)
$ErrorActionPreference = 'Stop'
if (-not $AuthorizeRbacChanges) { throw 'Scoped loader RBAC changes require -AuthorizeRbacChanges.' }
if (-not $PSCmdlet.ShouldProcess("$PrincipalId / $ResourceGroup", 'Grant loader permissions on the demo Search service and tutorials container only')) { return }
. (Join-Path $PSScriptRoot 'azure-common.ps1')
Assert-AzureContext $SubscriptionId $TenantId
Assert-DemoGroup $ResourceGroup $SubscriptionId
$search = Invoke-AzureCli @('search', 'service', 'show', '-g', $ResourceGroup, '-n', $SearchName, '-o', 'json')
$storage = Invoke-AzureCli @('storage', 'account', 'show', '-g', $ResourceGroup, '-n', $StorageName, '-o', 'json')
if ($search.tags.project -ne 'microsoft-live' -or $storage.tags.project -ne 'microsoft-live') {
    throw 'Targets are not demo resources.'
}
$assignments = @(
    @{ Scope=$search.id; Role='7ca78c08-252a-4471-8644-bb5ff32d4ba0' },
    @{ Scope=$search.id; Role='8ebe5a00-799e-43f5-93ac-243d3dce84a7' },
    @{ Scope="$($storage.id)/blobServices/default/containers/tutorials"; Role='ba92f5b4-2d11-453d-a403-e96b0029c9fe' }
)
foreach ($assignment in $assignments) {
    $existing = Invoke-AzureCli @('role', 'assignment', 'list', '--scope', $assignment.Scope,
        '--assignee', $PrincipalId.ToString(), '--role', $assignment.Role, '-o', 'json')
    if (@($existing).Count -eq 0) {
        $null = Invoke-AzureCli @('role', 'assignment', 'create', '--scope', $assignment.Scope,
            '--assignee-object-id', $PrincipalId.ToString(), '--assignee-principal-type', $PrincipalType,
            '--role', $assignment.Role, '-o', 'json')
    }
}
Write-Output 'Scoped loader assignments ensured. No runtime, subscription-wide or group-wide role was granted.'

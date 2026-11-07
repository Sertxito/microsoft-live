# Azure preparation and deployment gates

## Selected deployment update (2026-11-07)

**Deployed and verified:** https://ca-m365live-demo.thankfuldesert-86f8de10.westeurope.azurecontainerapps.io
Revision `ca-m365live-demo--demo20261107`, named traffic 100%; Search/Blob and
seven correlated Application Insights stages verified. See
[verification](verification-matrix.md) for actual checks and the initial cold
readiness 408. No cold-start latency guarantee or real rollback is claimed.

The owner approved deployment, then approved **ApiKey** authentication after
Graph denied directory application creation. This selected demo requires no
API/Postman Entra registration or OAuth consent. Managed identities for Azure
resource access remain unchanged. The Entra sequence below is retained for
the optional JWT path, not executed for this deployment.

The API key is a randomly generated 256-bit hexadecimal secret referenced from
Container Apps as `HARNESS_API_KEY`. It is never committed or printed. Requests
must use `X-API-Key`; query strings and Bearer JWTs cannot bypass key mode.
Missing/incorrect keys return 401. HTTPS and the same operator IPv4 /32 remain
mandatory. This is a shared demo credential, not per-user authorization.

`deploy-candidate.ps1 -AuthMode ApiKey -ApiKey $runtimeKey` does not read Entra
state. `-Action Validate`/`WhatIf` plus `-AuthorizeRemoteValidation` run preflight.
Secure ARM parameters use an owner-only temporary file deleted after the command.
Pass the key in a session variable, never a literal command or persisted script.
`set-demo-traffic.ps1 -ApiKey $runtimeKey` runs current smoke including wrong-key
401 rather than the JWT permission-specific 403 scenario.

After deployment, run `scripts\demo-azure.ps1 -Query "azure" -AuthorizeRemote`.
It uses current Azure CLI management authorization to retrieve the demo secret
in memory when no key is supplied, makes the protected request and prints only
retrieval results. To use Postman, import the separate credential-empty
`demo/postman/tutorial-search-api-key.postman_collection.json`; set the endpoint
and key only in local, unexported values. Rotate the key by updating the secret
and restarting the active revision under separately authorized operations.

The operational sequence below records the reviewed preparation and commands.
The owner subsequently authorized this deployment on 2026-11-07. Do not repeat
provisioning, uploads or permission changes merely by following the examples:
inspect the deployed resources and latest receipts first. Future broader access,
deletion, OAuth/Entra changes and shared infrastructure remain unauthorized.

## Target and cost review

- Subscription Visual Studio Professional: `8e6ace56-e0f2-4071-825a-a20363df34f8`.
- Tenant: `cf36141c-ddd7-45a7-b073-111f66d0b30c`.
- West Europe; isolated group proposed: `rg-microsoft-live-demo`.
- Baseline retail EUR, checked 2026-11-06: Search Basic approximately 66.21/month
  (0.0907/hour, 730 hours); ACR Basic approximately 4.55/month (0.1496/day).
- Approximately **70.76/month baseline**, plus Container Apps compute/requests,
  Blob, logs, network and cloud image builds. Taxes/contract discounts excluded.
  This is not a total quote or a configured spending limit. Scale-to-zero does
  not stop Search/registry charges; the 1-GB/day workspace ingestion cap is not
  an instantaneous or comprehensive financial cap.
- Source: [Azure Retail Prices API](https://prices.azure.com/api/retail/prices),
  EUR / `westeurope`, Search and Container Registry Basic.

Azure CLI and Bicep are present. Docker/azd are not required for this agreed
standalone Bicep + ACR cloud-build path, and were not installed. Providers and
regional resource-type availability were read; actual quotas/capacity, effective
deny policy, ACR cloud-build entitlement, RBAC/directory write rights and Entra
consent remain unverified. No quota extension was installed.

## What is prepared

- `infra/main.bicep`: identity, ACR Basic, Search Basic, authenticated private
  Blob container, Log Analytics/Application Insights, Consumption environment.
- `infra/app.bicep`: real digest-pinned application, user-assigned identity,
  protected health details, explicit token authority/audience and Azure search,
  HTTPS-only ingress with the operator IPv4 /32 and explicitly approved connector
  allow rules, 0-1 replicas. [Copilot Studio setup](integration-copilot-studio.md)
  documents the Europe change and credential-free import definition.
- `src/Harness.Api/Dockerfile`: patched, immutable SDK/runtime base images,
  non-root runtime; no test issuer or placeholder service.
- Search index schema and idempotent `mergeOrUpload` loader; synthetic catalog
  is stored in Blob and Search. This is a deliberate push loader, not a Blob
  indexer. Reruns do not delete unrelated documents and reject a merged >20 cap
  or incompatible existing fields.
- Explicit Entra, scoped-loader RBAC, source-upload/build, deployment, smoke,
  promotion and rollback scripts. No tokens/keys are written to state files.

Network endpoints for Blob/Search are public but authenticated, not VNet/private
endpoints. Use only this synthetic catalog. Runtime can query Search and pull
its image, not edit indexes or Blob. See [identity](identity-permissions.md).

## Local validation (no Azure write)

From the repository root:

```powershell
pwsh -NoProfile -File scripts\validate-azure-local.ps1
pwsh -NoProfile -File scripts\validate-local.ps1
```

The first compiles both templates and checks ARM security/scale/traffic
invariants, script syntax, image digest pins and catalog/index field alignment.
The second builds/tests the app, including fully mocked CLI/HTTP traffic
transitions. Neither is cloud acceptance or a successful Docker build.

## Operational sequence: only after separate authorization

Use PowerShell 7. Select/verify the approved Azure account yourself; scripts
reject a different current subscription or tenant and never silently switch it.
Replace runtime placeholders with explicitly reviewed values; do not save tokens.

```powershell
$context = @{
    SubscriptionId = '8e6ace56-e0f2-4071-825a-a20363df34f8'
    TenantId = 'cf36141c-ddd7-45a7-b073-111f66d0b30c'
}
$group = 'rg-microsoft-live-demo'
```

1. Review the exact Bicep plan/cost/roles and isolated-group inventory. Group
   creation is included only in an explicitly authorized Deploy action:

   ```powershell
   .\scripts\deploy-foundation.ps1 @context -ResourceGroup $group -Owner '<approved-owner>' `
       -Action Deploy -AuthorizeAzureChanges -AuthorizeRbacChanges
   ```

   Once the group exists, `-Action Validate` or `-Action WhatIf` with
   `-AuthorizeRemoteValidation` performs remote deployment validation/what-if.
   The deploy command does not pretend either was run beforehand. Do not
   continue if actual policy/capacity/roles differ from the approved design.
   Non-secret outputs go to ignored `.local/azure/foundation.json`.

2. Separately approve Entra creation, then:

   ```powershell
   .\scripts\prepare-entra.ps1 @context -Name 'm365live-demo' -AuthorizeEntraChanges
   ```

   It reconciles only uniquely named/tagged demo applications; no secret,
   app-role assignment or automatic tenant-wide consent. Reserve these names.
   Keep non-secret IDs in `.local/azure/entra.json`; obtain delegated PKCE
   tokens as described in [Postman](integration-postman.md).

3. Decide the **loader principal**, distinct from runtime. The foundation grants
   a loader UAMI scoped roles for use on an authorized Azure host. For a CLI
   workstation loader, separately approve the operator object ID and grants:

   ```powershell
   .\scripts\grant-demo-loader.ps1 @context -ResourceGroup $group `
       -PrincipalId '<approved-loader-object-id>' -PrincipalType User `
       -SearchName '<foundation-search-name>' -StorageName '<foundation-storage-name>' `
       -AuthorizeRbacChanges
   .\scripts\load-azure-knowledge.ps1 @context -ResourceGroup $group `
       -ExpectedLoaderPrincipalId '<approved-loader-object-id>' `
       -SearchName '<foundation-search-name>' -StorageName '<foundation-storage-name>' `
       -AuthorizeDataUpload
   ```

   CLI login must already be that identity. RBAC propagation can take time;
   errors stop the script, never fall back to keys or broaden permissions.
   Review/revoke temporary operator grants after loading.

4. Approve upload of the allowlisted application sources and synthetic catalog,
   cloud-build charges and immutable publication to the exact demo ACR:

   ```powershell
   .\scripts\build-azure-image.ps1 @context -ResourceGroup $group `
       -RegistryName '<foundation-registry-name>' -AuthorizeSourceUpload
   ```

   No Git/MCPEE/history/tests/node_modules/bin/obj are uploaded. Record the
   returned `registry/harness@sha256:...`; do not deploy mutable tags.
   ACR cloud build and the Linux image have not been executed locally.

5. Approve the candidate and the operator's current public IPv4 /32:

   ```powershell
   .\scripts\deploy-candidate.ps1 @context -ResourceGroup $group `
       -ImageDigest 'sha256:<actual-64-hex-digest>' -RevisionSuffix '<unique-lowercase-suffix>' `
       -SmokeClientCidr '<approved-ipv4>/32' -AuthorizeAzureChanges -AuthorizeBootstrap
   ```

   `-AuthorizeBootstrap` is necessary only for the first application. **There is
   no previous revision then:** its traffic serves the candidate only to the
   operator /32. It is not a zero-exposure bootstrap and has no rollback.
   Later deployments require a successful acceptance receipt, unchanged named
   stable traffic and unchanged access restrictions; stable remains at 100%.
   Preserve `.local/azure/candidate.json` and traffic receipts. Do not overwrite
   state with parallel attempts.
   For an MCP-enabled candidate, pass `-RequireMcpSmoke`. This records an explicit
   MCP promotion requirement; fresh initialize/discovery/tool-call and negative
   checks are performed alongside REST before any traffic change. See
   [native MCP setup](integration-mcp-copilot-studio.md).

6. With runtime tokens held only in session variables, explicitly run the
   promotion operation. It performs new smoke itself; old success files cannot
   skip the check:

   ```powershell
   .\scripts\set-demo-traffic.ps1 @context -Action Promote `
       -StatePath .local\azure\candidate.json -BearerToken $permittedToken `
       -ForbiddenBearerToken $validTokenWithoutSearchPermission `
       -AuthorizeAzureChanges -AuthorizeRemoteSmoke
   ```

   Smoke binds the Azure revision endpoint and its authenticated revision/mode,
   checks readiness, nonempty retrieval, sources/no synthesis, bad input,
   anonymous 401 and legitimate forbidden-token 403. No redirects. Platform TCP
   readiness probes prove only process availability, not dependency readiness.
   Promotion rechecks existing traffic, changes exactly one named revision to
   100%, verifies the result and stores a token-free receipt.

7. Roll back only after a later candidate has a recorded prior accepted revision:

   ```powershell
   .\scripts\set-demo-traffic.ps1 @context -Action Rollback `
       -StatePath .local\azure\candidate.json -AuthorizeAzureChanges
   ```

   The previous revision must still be active and have the exact recorded image;
   current traffic must still match this candidate. No guessing, deactivation,
   deletion or Git restore. A failed operation can leave resources/revisions:
   inspect state before retrying instead of launching parallel work.

## Acceptance and cleanup still required

Remote template validation, image execution, real Search/Blob access, correlated
Application Insights ingestion and bootstrap traffic acceptance have now run.
Consent is not needed for the selected API-key mode. Comprehensive Azure ranking/
latency thresholds and a real rollback have not run. Bootstrap cannot validate a
rollback until a second accepted revision exists. Existing local checkpoint
verification creates/restores no Git tag.

The owner cleans up manually only after reviewing the exact group ID, tenant,
subscription, tags, inventory and dependencies. Stop if anything is shared.
Directory apps/service principals/consents and operator role grants are not
removed merely by deleting an Azure group: review them separately. No cleanup
script or deletion is delivered, and residual costs must be checked by the owner.

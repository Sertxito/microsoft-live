# Verification: direct local implementation

Public release reproduction, 2026-11-07: exported only the Git-selected public
files into a fresh directory, restored dependencies and ran validate-local.ps1.
All 119 tests passed (17 unit, 1 architecture, 5 contract, 95 integration, 1 E2E);
11 projects built with zero warnings/errors. Both documented local queries
returned tutorial-001/tutorial-013, anonymous 401, authorized 200 and no generated
answer. No MCPEE workspace, Azure receipt, private config or npm dependency was
needed. Own-account Azure instructions were reviewed against existing scripts;
no second subscription deployment or successful Copilot Studio test is claimed.

MCP extension rechecked 2026-11-07: final full suite 118 PASS (17 unit, 1
architecture, 5 contract, 94 integration, 1 E2E), zero build warnings/errors.
Thirteen actual official-SDK transport tests cover authentication, discovery,
structured tool execution, argument validation/errors, timeout and shared limits;
mocked promotion proves MCP failure prevents traffic changes.
This concerns the demo MCP endpoint, not MCPEE's execution/lifecycle server.
See [native MCP integration](integration-mcp-copilot-studio.md). Earlier evidence
below is preserved as historical proof rather than overwritten.
After deployment, real REST and MCP candidate smoke passed; public `/mcp` smoke
passed at 2026-11-07T17:22:29Z. mcp20261107 serves 100% named traffic, previous
revision remains active, 72 ingress rules/HTTPS/key reference preserved. A
relative-state receipt failure after promotion was repaired without a second
Azure mutation; all final 34 operation-safety tests pass including its regression.
No actual Copilot Studio connection acceptance is claimed.

Observed on 2026-11-06 and extended/rechecked on 2026-11-07, outside MCPEE. No MCPEE CLI, MCP execution, lifecycle
transition or specification rewrite was performed. Approved artifacts retain
their original digests and historical state; this report does not mark them
implemented in the MCPEE index.

## Reproducible local evidence

`pwsh -NoProfile -File scripts\validate-local.ps1` completed successfully:

| Suite | Passed | Failed |
| --- | ---: | ---: |
| Unit | 17 | 0 |
| Architecture | 1 | 0 |
| Contract | 4 | 0 |
| Integration | 72 | 0 |
| Deterministic end-to-end evaluation | 1 | 0 |
| **Total** | **95** | **0** |

Build: 11 projects, zero warnings and zero errors. TRX files are local under
`TestResults/` (ignored by Git). Script syntax and demo JSON documents parsed
successfully. No tools or SDKs were installed; approved NuGet dependencies
were restored.

`pwsh -NoProfile -File scripts\validate-azure-local.ps1` also passed: both
standalone Bicep templates compile, generated ARM satisfies the selected
auth/key/HTTPS/IP/scale/traffic/role-scope invariants, all operational scripts
parse, base-image digests are pinned and Search fields match the catalog.
MCR manifest digests were read from the official registry; neither container
image nor application was built/published there.

Azure-specific tests include exact delegated scopes (including substring/case
rejection), no-server startup on invalid telemetry/identity configuration,
sanitized parent-correlated activities, authorization gates before adapter calls,
fresh-smoke promotion/rollback, failed smoke, wrong revision, stale traffic,
missing previous revision and forbidden-token bypass rejection. Fully mocked
CLI tests also exercise new/existing indexes, repeated merge loading, schema
conflict, wrong loader, merged catalog cap and explicit partial-batch failure.
These tests contact neither Azure nor a real remote HTTPS target.

The official `azure-validate` workflow was completed on 2026-11-07 after the
owner approved deployment. Foundation and API-key application validate/what-if
passed against the real target. Policies/capacity and live scoped roles were
checked. The plan is `Validated`; actual acceptance evidence follows below.

The evaluation executes 16 reference queries against the authenticated HTTP
pipeline and enforces the thresholds in `evaluations/thresholds.json`: 100%
expected-result coverage, 100% response correlation, 100% result sources,
zero unauthorized/inactive documents and zero generated answers in that set.
These are deterministic local results, not Azure ranking or latency evidence.

`demo-local.ps1 -Query "container apps"` returned HTTP 200 with `tutorial-001`,
source and no synthesis. `"microsoft foundry"` returned `tutorial-013`.
Both demonstrations observed public liveness 200, anonymous capabilities 401,
authorized readiness 200, and all seven evidence-stage names.

A separate bounded Kestrel process also returned minimal liveness 200 and a
correlated readiness 401 with no token. That process was stopped immediately
after verification. This did not validate operational issuer metadata or Entra.

## Relationship to the approved checks

The original checks mix implementation, historical MCPEE repair and Azure
acceptance. They have not all been executed or passed:

| Check | Current evidence / status |
| --- | --- |
| CHECK-001 | Not executed: MCPEE lifecycle inspection excluded from this direct task. |
| CHECK-002 | Passed: local prerequisite check; Azure readiness intentionally unverified. |
| CHECK-003 | Passed: `dotnet build Harness.sln --no-restore`. |
| CHECK-004 | Unit suite passed (17 cases); timeout/error behavior also tested in integration. |
| CHECK-005 | Architecture suite passed; Domain/Application have no cloud/HTTP dependencies. |
| CHECK-006 | Contract suite passed: actual response fields, OpenAPI and correlated early errors. |
| CHECK-007 | Local loading/auth/health/evidence/checkpoint failure tests and mocked Azure loading/promotion/rollback simulations passed. No Azure acceptance. |
| CHECK-008 | Deterministic HTTP evaluation passed for 16 reference queries. |
| CHECK-009 | Passed: local compiled ARM checks and real foundation/application validate/what-if; policy and regional quota review completed. |
| CHECK-010 | Local artifact-safety test passed for empty Postman credential variables and absent production test issuer; Azure scripts parse and key/role boundaries are checked. Not a comprehensive secret audit. |
| CHECK-011 | Passed for selected API-key mode: real HTTPS smoke, exact revision/mode, 200/400/401 including missing/wrong key, nonempty sources/no synthesis and verified 100% named traffic. JWT-specific 403 remains a local test. |
| CHECK-012 | Azure Search/Blob loading, runtime identity readiness and seven correlated Application Insights stages verified live. Real rollback, all relevance/latency thresholds and tenant JWT/Postman acceptance not claimed. |
| CHECK-013 | Passed: Git root resolves to this repository. |
| CHECK-014 | Passed: origin is `https://github.com/Sertxito/microsoft-live`; no remote contact. |
| CHECK-015 | Executed: existing agent-host history was visible. No commit, tag, fetch or push was created by this implementation. Existing history is not proof of named demo checkpoints. |
| CHECK-016 | Blocked for a real checkpoint: no explicitly selected tag/manifest. The verifier fails closed on a nonexistent tag in a regression test; nothing was created or restored. |
| CHECK-017 | Not executed: historical MCPEE recovery is excluded from this direct implementation. |

## Scope and remaining work

Implemented: deterministic catalog/search, strict contracts, shared application
handler, real JWT checks, role/delegated-scope authorization, protected details, controlled
errors/timeout/rate limiting, bounded local evidence, Azure textual-query adapter
with local transport tests, runnable test-host demonstration, local seed and
verification scripts, and credential-free Postman collection. Azure preparation
now includes Bicep, immutable container packaging, Entra/loader/bootstrap scripts,
opt-in cloud telemetry and guarded candidate/promotion/rollback operations.

Existing files were integrated, not discarded. The catalog was extended with
the missing Foundry topic to 13 synthetic entries. No model or real Foundry
dependency was activated. The existing JSON catalog remains the local seed
format instead of creating unused per-tutorial Markdown placeholders.

Still deferred: real rollback (bootstrap has no predecessor), CI, real checkpoints,
tenant JWT/Postman/Copilot Studio acceptance and comprehensive Azure relevance/
latency thresholds. azd is not required by the agreed Bicep recipe.
The installed ASP.NET Core shared framework is 10.0.12 while the checked support
policy lists 10.0.14. The prepared image pins ASP.NET 10.0.14; no local runtime
update or image execution was performed.

## Actual Azure deployment: 2026-11-07

Owner-approved provisioning, resource-scoped RBAC, allowlisted source publication,
synthetic catalog upload and API-key deployment completed. Entra registration
creation was denied; the owner approved shared API-key consumer authentication
instead. No Entra application/consent/client secret, deletion or MCPEE repair
validation is claimed.

- Endpoint: https://ca-m365live-demo.thankfuldesert-86f8de10.westeurope.azurecontainerapps.io
- Active revision: `ca-m365live-demo--demo20261107`, Provisioned/Healthy, 100% traffic.
- Image digest: `sha256:4027d827be8dbcb955297c181e0d840bf03ea49bd983094c974107560eb96794`.
- HTTPS required; one approved operator IPv4 /32; secretRef key, no value in
  revision environment/state. Runtime/loader five scoped assignments verified.
- Blob synthetic catalog uploaded; 13 Search documents merged.
- Fresh real smoke passed before acceptance receipt. First protected readiness
  request timed out at five seconds during initial identity/dependency cold
  initialization (408). The next diagnostic request returned 200 and the full
  smoke then passed without changing deadlines or adding an anonymous fallback.
  Scale-to-zero remains enabled; cold-start latency is not guaranteed.
- Query `container apps` returned tutorial-001, source, null generated answer,
  duration 133 ms, correlation `37c40f0b-b50a-4fdc-b8be-5a27fc34bbb3`.
- Log Analytics AppDependencies query for that correlation returned all seven
  stages: auth.validate, capability.route, search.query, response.validate,
  authorization.check, http.request and evidence.write (one each).
- Token-free candidate/traffic receipts under ignored `.local/azure`; the key
  is stored only in Azure's Container Apps secret plus transient process memory.

Run `scripts\demo-azure.ps1 -Query "container apps" -AuthorizeRemote` from this
workstation's allowed IP. It obtains the secret in memory using current operator
CLI management rights and prints only results. No OAuth app login is needed.

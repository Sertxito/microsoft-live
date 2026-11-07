# Local operations and operational limits

Selected Azure demo: explicit ApiKey mode instead of an Entra consumer login.
It requires `HARNESS_API_KEY` through a Container Apps secret reference; never
log it, set it in a URL or save it in a collection/script. JWT remains the default
optional mode. The key gives shared search permission, not user-specific roles.
`scripts\demo-azure.ps1 -Query "azure" -AuthorizeRemote` reads the configured
secret using the operator's Azure CLI permissions in memory and prints only
retrieval results. It creates neither login applications nor OAuth consent.

Start with [Demo 01](demo/DEMO-01-LOCAL.md). Local seed data is synthetic and
deterministic. Preserve existing work; seed only to an explicit local destination.
The catalog contains 13 documents; inactive and operations-audience entries
must never appear in community results.

The API records `auth.validate`, `authorization.check`, `capability.route`,
`search.query`, `response.validate`, `http.request` and `evidence.write`.
`HarnessTelemetry.Find(correlationId)` returns only that identifier's in-memory
records; no-match returns an empty list. The console demo displays stage names.
This store is bounded to 4096 entries, lost on process exit, and is not durable
audit storage. The same sanitized metadata is exposed through `Harness.Evidence`
activities. Explicit Azure-only OpenTelemetry export was verified for all seven
stages in the deployed Application Insights workspace.

Search/readiness deadlines are five seconds. Search has an 8-KiB request limit.
Errors include a safe code, message and correlation ID. Reuse a GUID
`X-Correlation-ID` for investigation; other values are replaced with a generated
GUID. See [security](security.md) for rate limiting and identity boundaries.

Azure mode requires `HARNESS_MODE=AzureIntegrated`, `HARNESS_AUTHORITY`,
`HARNESS_AUTH_AUDIENCE`, `HARNESS_SEARCH_ENDPOINT`, `HARNESS_SEARCH_INDEX` and
`HARNESS_SEARCH_MINIMUM_SCORE` and `HARNESS_MANAGED_IDENTITY_CLIENT_ID`.
Optional export additionally requires `HARNESS_TELEMETRY_EXPORT=true` and
`APPLICATIONINSIGHTS_CONNECTION_STRING`. The score is Azure-specific and must be measured;
do not copy the local 0.2 threshold as a claim of equivalent relevance.
Missing configuration fails startup without a local fallback.

Azure provisioning, indexing, Blob upload, runtime identity, remote stage
telemetry and bootstrap traffic acceptance were verified on 2026-11-07.
Real rollback and CI publication are not validated.
`setup-check.ps1 -Mode AzureIntegrated` intentionally reports remote readiness
unverified. [Deployment](deployment.md) documents the prepared, opt-in operations.

Candidate and traffic receipts under `.local/azure` contain IDs, revision/image
metadata and smoke outcomes, never tokens. Preserve them between operations.
The next candidate requires the latest successful traffic receipt and unchanged
network/traffic configuration. Smoke runs again inside promotion, not from an old
success file. Failed deployments may leave resources or revisions; inspect
their actual state rather than launching parallel/replacement operations.

After deployment, verify Application Insights by a freshly supplied correlation
GUID and all stage names, not merely by resource existence. Example query:

```kusto
AppDependencies
| where TimeGenerated > ago(30m)
| where tostring(Properties["correlation.id"]) == "<runtime-correlation-guid>"
| project TimeGenerated, Name, Properties
```

Exporter table/tag mapping, ingestion delay, managed-identity propagation, Azure
ranking/latency and rollback availability require real acceptance. If stage
activities are mapped to a different table, inspect that resource's schema
before claiming the query proves ingestion. No body/token/query logging is needed.

Per the approved cleanup decision, the owner removes the isolated resource group
manually after inspecting tenant/subscription, exact resource-group ID, tags,
resource inventory and dependencies. Stop if anything is shared or ambiguous.
No cleanup script or deletion was executed; residual costs cannot be ruled out
until the owner verifies removal and remaining dependencies.

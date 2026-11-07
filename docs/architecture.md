# Tutorial search harness architecture

The solution separates Domain (tutorial records), Contracts (DTOs), Application
(`TutorialSearchSpecialist` and ports), Infrastructure (catalog, local/Azure
search and bounded local evidence), and Api (HTTP, JWT, authorization and errors).
All consumers use the same specialist. The API does not duplicate retrieval.

`LocalDeterministic` reads 13 synthetic tutorials from
`knowledge/tutorials/catalog.json`, covering the ten required topics, an inactive
document and a restricted audience. JSON is the authoritative local seed format;
individual Markdown tutorial paths from the plan were not created merely to
satisfy a path inventory. Sources under `example.invalid` are deliberately
non-resolving synthetic identifiers, not verified public tutorials.

Matching is lexical, deterministic, case-insensitive, ordered by score then ID,
with a local minimum score of 0.2. Only active `community` documents are returned.
The maximum is five, and `generatedAnswer` is always null. This is not semantic
search, model inference, or proof of equivalent ranking in Azure.

`AzureIntegrated` uses Azure AI Search SDK with server-side status/audience
filters and managed identity. Endpoint, index and an explicitly measured
provider-specific minimum score and user-assigned managed identity client ID are mandatory. Failure never selects the local
catalog. Its transport/error behavior has local tests. Azure loading, scoped
RBAC, dependency readiness and one expected query are now verified live;
comprehensive Azure relevance/latency thresholds remain unmeasured.

The production HTTP host requires an HTTPS authority and token audience,
validates JWT signature/issuer/audience/lifetime, and requires the
`Tutorials.Search` application role or exact delegated scope. Liveness is public and minimal. Readiness and capabilities
are protected. Search has a five-second deadline, an 8-KiB Kestrel request limit,
a second bounded JSON reader, strict unknown-property rejection and a 30-request
per-minute instance-wide fixed window (not a distributed tenant quota).

`HarnessTelemetry` retains at most 4096 stage records in memory. It captures
correlation, outcome, duration, count, assembly version and revision, not query
text, tokens, claims or documents. Sanitized stage activities can be exported by
the Azure Monitor OpenTelemetry SDK only when Azure mode explicitly enables
`HARNESS_TELEMETRY_EXPORT=true` and supplies an Application Insights connection
string. Local mode rejects that export setting. There is no public evidence endpoint.

For the explicitly approved no-Entra Azure demo, `HARNESS_AUTH_MODE=ApiKey`
selects a separate authentication scheme with header-only `X-API-Key`, requiring
a configured 256-bit secret. It does not accept JWTs or anonymously retrieve;
the default Jwt mode never accepts keys. The authenticated shared-key identity
has only Tutorials.Search application permission, with the same endpoint gates.
Azure managed identity remains separate from consumer authentication.

The prepared Azure topology uses Container Apps Consumption (0-1 replicas), ACR
Basic, Search Basic, private authenticated Blob storage and workspace-backed
Application Insights. Runtime and loader identities have different resource-scoped
roles. Network endpoints remain public but authenticated; no private-endpoint or
VNet isolation is claimed. Demo HTTPS ingress preserves the operator IPv4 /32
and, when explicitly approved, the official connector ranges for its Geo.
See [deployment](deployment.md) for authorization gates and bootstrap limitations.

The `/mcp` endpoint uses the official MCP ASP.NET SDK and stateless Streamable
HTTP, calls that same specialist and requires the same permission/rate limit.
Only buscar_tutoriales is exposed. See [MCP integration](integration-mcp-copilot-studio.md).

The executable under `tests/Harness.LocalDemo` uses the real HTTP pipeline with
an in-process test server and ephemeral RSA-signed JWTs. Its issuer and signing
key are exclusively test-host configuration; they are not in the production API.
It exits without leaving a background service, credentials or Azure resources.

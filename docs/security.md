# Security boundaries

- Explicit ApiKey mode is available only by deployment configuration: a 256-bit
  hexadecimal secret, constant-time digest comparison, header-only acceptance,
  no anonymous/JWT fallback. It gives shared demo access, not user-specific roles.
  Invalid/multiple/missing headers cannot retrieve. The selected Azure deployment
  also requires HTTPS and one approved source IPv4 /32.

- Production accepts signed JWTs from the configured HTTPS authority for the
  configured token audience. Signature, issuer, audience and lifetime are checked.
- The `Tutorials.Search` role or exact whitespace-delimited delegated scope is
  required before invoking the specialist; substring/case variants are denied.
  Document audience `community` is separate from the JWT audience.
- Anonymous liveness returns only `{"status":"live"}`. Readiness and capabilities
  require authorization. Unknown routes have correlated errors.
- Tests cover missing/malformed/expired/wrong-signature/wrong-issuer/wrong-audience
  JWTs and missing role; none may query the index.
- Invalid input is rejected before retrieval. Upstream inactive or wrong-audience
  results are rejected, never leaked. Provider failure is 503, not local fallback.
- Test signing keys exist only in process memory under `tests`, never in the
  production host. No operational authentication bypass, stored bearer token,
  client secret or Azure key was added.
- The local collector records only bounded stage metadata. Azure Monitor export
  is explicitly opt-in and rejected in local mode. Do not log request bodies,
  authorization headers, queries or documents. Seven stage activities were
  verified in Application Insights for a real correlated Azure request.
- Built-in rate limiting is instance-wide, not a distributed abuse defense.
  A gateway and real Entra/RBAC acceptance remain deployment work.
- Prepared Bicep disables Search API keys, Blob shared keys/public blobs, and
  registry admin authentication. Public network endpoints are not private links.
- Operational scripts reject missing authorization before CLI/HTTP calls. Cloud
  build stages only allowlisted source; no repository history, MCPEE state or
  test signing material is included. Only reviewed synthetic data is loadable.
- Candidate promotion performs fresh authenticated smoke, exact Azure mode and
  revision binding, plus missing/wrong-key 401 checks in key mode or JWT 401/403 checks. Stale traffic or missing accepted
  rollback identity fails closed. Initial bootstrap was restricted to the operator /32
  and has no earlier revision; it is not a zero-exposure deployment.
- Owner approved the Europe connector ranges for Copilot Studio. These shared
  Microsoft IPs are not tenant isolation; header API key and HTTPS remain required.
  Network-only updates preserve runtime identity, revision/image, secrets and traffic.
  See [connector configuration](integration-copilot-studio.md).
- `/mcp` requires the same search permission and selected credential as REST,
  including initialize and discovery. Stateless Streamable HTTP exposes only
  buscar_tutoriales, shares the instance rate limit, validates arguments and
  keeps the five-second retrieval deadline. No command execution, legacy SSE,
  public anonymous discovery or additional browser CORS permission is exposed.

Do not expose the test demo host as a production service. Do not export populated
Postman credentials. Permission grants, deployment and external project-data
transfer are not allowed outside the explicitly approved isolated demo.
Owner-approved scoped role grants, synthetic/catalog source transfer and
deployment were performed on 2026-11-07; no Entra app or global consent was created.

# Postman integration

## Show the deployed MCP (not REST)

Import [the MCP collection](../demo/postman/tutorial-search-mcp.postman_collection.json)
in Postman Desktop. Set the collection variable `baseUrl` locally to
`https://ca-m365live-demo.thankfuldesert-86f8de10.westeurope.azurecontainerapps.io`
(no trailing slash). In Postman Vault, create a secret named `apiKey` with the
current Azure Container Apps api-key value. The collection uses
`{{vault:apiKey}}`; do not put the value in synchronized collection/environment
variables. Use the Desktop client from the approved operator IP; a cloud runner
can use a different, blocked source IP. Never export or share populated credentials.

Send requests 01-07 in order (or use the Desktop collection runner with Vault
access enabled). Show the Post-response test results:

- 01: HTTP 200, initialize negotiates MCP 2025-03-26 with tools.
- 02: HTTP 202, initialized notification accepted.
- 03: HTTP 200, tools/list exposes only buscar_tutoriales.
- 04: HTTP 200, tools/call returns tutorial-001 and a correlated source,
  generatedAnswer=null. Sources are synthetic, not live published tutorials.
- 05: HTTP 200 with isError=true/validation_error for invalid input.
- 06/07: HTTP 401 for missing/wrong key.

The shared test script understands both JSON and Streamable HTTP SSE response
envelopes. This is not the deprecated separate SSE transport.
If cold start produces a timeout, show it explicitly and deliberately retry;
do not imply guaranteed first-call latency or disable authentication.
These checks establish protocol/retrieval availability at the deployed endpoint,
not a guarantee of continuous uptime or Copilot Studio DLP compatibility.
Postman UI execution is user-side; automated wire verification is separate.
On 2026-11-07, the seven exact collection requests and 19 shared JavaScript
assertions passed against the public deployed MCP using a local HTTP/JavaScript
harness. Credentials stayed in memory; no Postman UI or cloud workspace was
operated. The harness normalized cross-context arrays to match deep-equality
semantics; that harness fix did not require a server or collection change.

For the selected no-Entra demo, import
`demo/postman/tutorial-search-api-key.postman_collection.json` instead. Use
local, unexported `baseUrl`/`apiKey` values and the `X-API-Key` header. Obtain the
secret through the authorized Container Apps portal or `demo-azure.ps1`, which
uses it internally without printing. Do not put it in a URL, source file or
exported collection. The JWT/PKCE instructions below are an optional alternative.

Import `demo/postman/tutorial-search.postman_collection.json`. Set `baseUrl` and
`bearerToken` at runtime using local, non-exported values for an authorized HTTPS
deployment. The collection contains no stored credentials or fixed destination.
Inspect the deployment's `/openapi.json` for the public search contract.

The collection checks successful search, invalid input (400), missing token (401),
minimal liveness and protected readiness/capabilities. To test 403, use a separately
issued valid token without `Tutorials.Search`; do not edit or fabricate a production
token. To test 503, use an explicitly authorized isolated dependency-failure scenario,
not shared Azure services. Automated local tests already exercise both branches.

The local console demo uses an in-process test server, not a listening Postman
endpoint. It demonstrates the same contract without needing credentials.
Real Postman execution has not been performed.

After separately authorizing and running the Entra bootstrap, use its non-secret
`.local/azure/entra.json` values with Postman OAuth 2.0:

- Grant: Authorization Code (with PKCE), SHA-256; authorize using the browser.
- Authorization URL: `https://login.microsoftonline.com/<tenantId>/oauth2/v2.0/authorize`.
- Access token URL: `https://login.microsoftonline.com/<tenantId>/oauth2/v2.0/token`.
- Client ID: `postmanClientId`; client secret blank.
- Callback: `https://oauth.pstmn.io/v1/browser-callback`, registered as public client.
- Scope: `api://<apiClientId>/Tutorials.Search`; use local runtime values only.

Tenant user-consent policy may require separately approved admin consent. The
bootstrap does not grant it. Do not substitute `/.default` and assume the
requested delegated permission exists. Supply a separate legitimately issued
token without the search scope/role for the deployment smoke 403 check.
Export neither tokens nor populated collection/environment variables.

Postman is the initial consumer per the approved decision. Copilot Studio
authentication and compatibility remain unverified in the actual tenant.

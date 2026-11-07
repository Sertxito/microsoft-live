# Connect Copilot Studio to the demo MCP server

This is a real MCP server, not the REST search operation and not MCPEE.
It uses Streamable HTTP at:

`https://ca-m365live-demo.thankfuldesert-86f8de10.westeurope.azurecontainerapps.io/mcp`

Public deployment/test evidence is recorded in [verification-matrix.md](verification-matrix.md).
Do not assume a successful maker connection until testing from your environment.

The presenter's maker connection was blocked by the DLP policy
`PowerApps Policy without CDS`. This is not a successful Copilot Studio
end-to-end demonstration. Use [your own deployment](demo/AZURE-EN-TU-CUENTA.md)
and the [presentation script](demo/GUION-DEMO.md) to try it in your environment.

Deployed and verified on 2026-11-07: mcp20261107 at 100% named traffic, official
SDK 2.4.0, public initialize/discovery/tool execution and negative auth/input
smoke passed. REST smoke also passed; the previous accepted revision remains
active for an explicitly approved rollback. Key, HTTPS and 72 ingress rules
are preserved. Actual Copilot Studio maker connection is still pending.

## Copilot Studio steps (Spanish UI)

1. Enable generative orchestration in your agent.
2. Herramientas > Agregar herramienta > Nueva herramienta > Model Context Protocol.
3. Name: `Tutoriales Microsoft`.
4. Description: `Busca tutoriales Microsoft del catalogo de demostracion.
   Devuelve titulos, resumenes y fuentes sinteticas. No genera respuestas ni
   verifica enlaces externos.`
5. Server URL: the full HTTPS `/mcp` endpoint above. Do not enter `/api/tutorials/search`.
6. Authentication: API key; type Header; header name `X-API-Key`.
7. Create a connection and enter the existing key only in the secure connection
   form. Get it with your authorized Azure Portal access: resource group
   rg-microsoft-live-demo > ca-m365live-demo > Secrets > api-key.
   Never send it in chat, agent instructions, URL/query or an exported file.
8. Add the server/tool to the agent. Discovery should list only `buscar_tutoriales`.
9. Test: `Busca tutoriales sobre Container Apps`. It should call the MCP tool
   and return tutorial-001. Inputs: query from user; maxResults 1-5 (default 5);
   audience community. Surface errors/empty results rather than inventing content.

No Swagger upload is required for the native MCP onboarding wizard. The existing
[Swagger file](../demo/copilot-studio/tutorial-search.swagger.json) is **REST only**
and is not an MCP connector definition.

## Behavior and limitations

- Same retrieval specialist/catalog and managed identity as REST; no second
  backend, model or dependency lookup. MCP responses include JSON text and
  structuredContent with correlationId, query, results, generatedAnswer=null,
  durationMs. Controlled failures use isError=true with correlated error data.
- Stateless Streamable HTTP, no in-memory client session or legacy `/sse`.
  Authentication is required for initialize, discovery and tool execution.
- The application shares the 30/min instance limiter with REST, enforces query
  3-200 characters, maxResults 1-5, community only and a five-second search deadline.
- Sources are synthetic `example.invalid`, not real accessible documentation.
- Existing Europe connector IP rules are shared Microsoft egress, not tenant
  isolation. No Internet-wide opening or key rotation is required.
- Scale-to-zero may cause cold-start timeouts; do not imply guaranteed first-call
  latency. Review DLP/licensing/connectivity if the wizard or connection is blocked.
- A real MCP wire/SDK smoke is necessary before promoting this image; an HTTP
  liveness probe or successful REST request alone is insufficient.
- No Copilot Studio agent/connection creation or publication is automated here.

Official reference:
[Connect an existing MCP server](https://learn.microsoft.com/en-us/microsoft-copilot-studio/mcp-add-existing-server-to-agent).

# Consume the demo from Copilot Studio

For the requested **MCP** integration, use [the MCP guide](integration-mcp-copilot-studio.md).
This document describes the alternative REST integration, not an MCP server.

Import [the Swagger 2.0 file](../demo/copilot-studio/tutorial-search.swagger.json).
It contains the exact deployed HTTPS host, only `buscar_tutoriales`, and only
header API-key authentication. Existing public OpenAPI 3.1 is unchanged.
Swagger 2.0 cannot express a null-only field: generatedAnswer is represented as
nullable string with an explicit always-null description; the API still never
generates an answer.

## Agent configuration

1. Open the agent, Tools > Add tool > New tool > REST API (preview). If unavailable
   in your environment, create a Power Platform custom connector by importing
   this same Swagger 2.0 and add that connector as an agent tool.
2. Upload the Swagger file. Select the solution and describe its purpose.
3. Authentication: API key; label `Clave de la demo`; parameter `X-API-Key`;
   location Header. Never select None or put the key in a query/body.
4. Select buscar_tutoriales. Fill query from the user's tutorial question,
   maxResults = 5, audience = community.
5. Create the connection with the actual key through the secure connection form,
   not agent instructions, knowledge, chat, source files or exported collections.
   In Azure Portal: rg-microsoft-live-demo > ca-m365live-demo > Secrets > api-key.
   The operator needs permission to view this secret. Do not send it to this chat.
6. Test `Busca tutoriales sobre Container Apps`. Expect tutorial-001 with its
   title/summary/source, no synthesized backend answer. Do not publish until this
   actual connector call works.

Tool description:

> Busca tutoriales sobre tecnologias Microsoft. Muestra los titulos, resumenes
> y enlaces devueltos. No inventes tutoriales ni fuentes. Si la busqueda falla
> o devuelve cero resultados, dilo claramente.

The catalog/source URLs are deliberately synthetic (`example.invalid`); returned
links are not real published tutorials. Do not present them as verified external
documentation. This is an API tool, not an MCP endpoint or knowledge source.

## Europe network access

Owner approved Europe connector access. Use current Service Tag Discovery API
prefixes for AzureConnectors.NorthEurope/WestEurope and
PowerPlatformPlex.NorthEurope/WestEurope, alongside existing operator access.
These are shared Microsoft ranges, **not tenant isolation**. HTTPS and the
random API key remain required; images, revisions and traffic are unchanged.

Applied and verified on 2026-11-07: 71 connector IPv4 ranges plus the original
operator /32 (72 Allow rules). Live authenticated smoke passed after warm-up;
anonymous and wrong-key retrieval still return 401. Runtime/image/traffic and
identity stayed unchanged. Cold starts can time out: no deadline was relaxed and
an actual Copilot Studio call is still pending.

`set-copilot-access.ps1` previews by default, refuses missing/mixed allow-lists
and requires explicit -AuthorizeNetworkChanges for Apply. It skips IPv6 because
Container Apps ingress IP rules accept IPv4. Preserve its token-free access
receipt under .local/azure for later candidate deployments.
Repeated Apply with no missing prefixes does not issue another PATCH. It waits
for Succeeded provisioning before recording verified access.

Refresh the official prefixes at least every 90 days and review changes.
The script adds missing prefixes without silently removing existing access;
retired rules require separately approved cleanup. HTTP built-in connector
flows or a different environment Geo may need other documented ranges; do not
open 0.0.0.0/0 to mask an incorrect configuration.

Troubleshooting:

- Import/schema failure: use the supplied v2 file, not the JWT-first public v3 file.
- 401: incorrect/missing key or header; fix the connection, not authentication code.
- 403 without an API correlation ID: check connector Geo/outbound route and network.
- 408/503: dependency/cold-start issue; surface it and retry deliberately, not silently.
- DLP/connector restrictions/license: review Power Platform environment policy.
- Agent does not call the tool: review its description and input mapping.

No maker connection, agent import/test, secret transfer or publication has been
performed by the code/network preparation. Only an actual Copilot Studio test
confirms end-to-end compatibility in that environment.

References:
- [REST API tools](https://learn.microsoft.com/en-us/microsoft-copilot-studio/agent-extend-action-rest-api)
- [Managed connector outbound ranges](https://learn.microsoft.com/en-us/connectors/common/outbound-ip-addresses)
- [Swagger 2.0 custom connectors](https://learn.microsoft.com/en-us/connectors/custom-connectors/define-openapi-definition)

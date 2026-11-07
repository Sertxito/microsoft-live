# Demo 03: Copilot Studio + MCP (tenant connection blocked)

The local executable exercises the protected HTTP contract and shared specialist
with real test-signed JWT validation. Run [Demo 01](DEMO-01-LOCAL.md).

The real MCP endpoint was deployed and tested through initialize, tools/list and
tools/call with API-key authorization. The
[MCP Postman collection](../../demo/postman/tutorial-search-mcp.postman_collection.json)
has seven requests and 19 assertions verified against that deployed endpoint
by an HTTP/JavaScript harness (not by operating Postman's UI).

In the presenter's Copilot Studio environment, `PowerApps Policy without CDS`
blocked connection creation. End-to-end integration remains unvalidated.
Each viewer can try [their own Azure deployment](AZURE-EN-TU-CUENTA.md) and tenant,
subject to DLP, licensing and administrative permissions.
Follow the [explanatory guide with copy-paste examples](GUION-DEMO.md) and
[native MCP guide](../integration-mcp-copilot-studio.md). No DLP bypass is provided.

# Demo 02: deployed Azure API-key demo

Endpoint:
https://ca-m365live-demo.thankfuldesert-86f8de10.westeurope.azurecontainerapps.io

This host is historical presenter evidence, not a public service with shared
credentials. To reproduce, use [your own Azure account](AZURE-EN-TU-CUENTA.md) and
the [three-demo guide](GUION-DEMO.md). Do not request the presenter's key.

The owner approved a no-Entra consumer demo: `X-API-Key`, HTTPS, the
approved workstation IPv4 /32 and later the official Europe connector ranges.
Azure managed identity still protects Search.
The API does not expose a web UI. A browser can inspect minimal `/health/live`;
search and readiness require the secret key.

From this workstation, using current Azure CLI management access:

```powershell
pwsh -NoProfile -File scripts\demo-azure.ps1 -Query "container apps" -AuthorizeRemote
```

The script gets the configured secret in process memory and prints only results.
For Postman, use the credential-empty API-key collection in
[integration](../integration-postman.md); never export a populated secret.

See [verification](../verification-matrix.md) for the real smoke, expected
tutorial-001 result, Search/Blob load and seven correlated telemetry stages.

Required future evidence: deployed revision, managed identity, real Blob/Search
loading, authorized protected health, smoke before promotion, and remote telemetry.
Resources are now billable: approximately 70.76 EUR/month fixed retail baseline
plus usage. Scale-to-zero remains 0-1; an initial protected readiness request
timed out before a warmed retry succeeded, so cold-start latency is not guaranteed.
The later MCP candidate has an active accepted predecessor for a separately
requested rollback; no actual rollback was demonstrated. No deletion, global consent or
consumer Entra registration was performed.

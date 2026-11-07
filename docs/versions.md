# Runtime and dependency baseline

| Component | Selected version | Support evidence | Notes |
| --- | --- | --- | --- |
| .NET SDK | 10.0.401 | [Microsoft .NET support policy](https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core), consulted 2026-11-04 | SDK version observed in the previous local setup check; pinned in `global.json`. |
| .NET target framework | `net10.0` | Same policy; .NET 10 is LTS and active, with support through 2028-11-14 | Latest patch must be installed to remain supported; no runtime installation or update is performed here. |
| JWT middleware | `Microsoft.AspNetCore.Authentication.JwtBearer` 10.0.14 | [NuGet](https://www.nuget.org/packages/Microsoft.AspNetCore.Authentication.JwtBearer/10.0.14), checked 2026-11-06 | Explicitly authorized and restored. |
| Azure search client | `Azure.Search.Documents` 11.7.0 | NuGet restore succeeded on 2026-11-06 | Textual query; real demo loading/readiness/search verified on 2026-11-07. |
| Managed identity | `Azure.Identity` 1.21.0 | [NuGet](https://www.nuget.org/packages/Azure.Identity/1.21.0), explicitly approved on 2026-11-06 | Aligns with Azure.Core 1.60 from telemetry; 1.17 produced duplicate managed-identity types. |
| Cloud telemetry | `Azure.Monitor.OpenTelemetry.AspNetCore` 1.6.0 | [NuGet](https://www.nuget.org/packages/Azure.Monitor.OpenTelemetry.AspNetCore/1.6.0), explicitly approved/restored on 2026-11-06 | Azure-only explicit opt-in; seven correlated stages verified on 2026-11-07. |
| MCP HTTP server | `ModelContextProtocol.AspNetCore` 2.4.0 | Official SDK restored/built/deployed on 2026-11-07 | Stateless Streamable HTTP; real initialize/discovery/tool smoke passed. |
| HTTP testing | `Microsoft.AspNetCore.Mvc.Testing` 10.0.14 | NuGet restore succeeded on 2026-11-06 | Test projects and local demonstration host only. |
| Test runner | Microsoft.NET.Test.Sdk 17.14.1; xunit 2.9.3; xunit.runner.visualstudio 3.1.1 | NuGet restore succeeded on 2026-11-06 | Explicitly authorized test dependencies, not production references. |

The support policy was checked again on 2026-11-06 and lists .NET 10.0.14 as
the current patch. Locally observed: SDK 10.0.401, .NET runtime 10.0.14, but
ASP.NET Core shared framework 10.0.12. Local compilation/tests pass; this does
not make the older ASP.NET patch current. Update the operational ASP.NET runtime
through a separately authorized installation before claiming a fully patched
deployment. No SDK or runtime was installed by this implementation.

The prepared Bicep uses stable resource APIs accepted by the installed Bicep
compiler: App 2025-07-01, Search 2023-11-01, Storage 2023-05-01, ACR 2023-07-01,
OperationalInsights 2023-09-01, Insights 2020-02-02, ManagedIdentity 2024-11-30
and Authorization 2022-04-01. Compiler acceptance is not remote deployment validation.

Official MCR manifests verified on 2026-11-06:

- SDK `10.0.401`, digest `sha256:e70cdb7f80b0348f5cb85f19a8f670fca061f033d57eed12fa003d58b0e06317`.
- ASP.NET `10.0.14`, digest `sha256:1a48394b6f29d3a32c79d9edecd4abda0ecbe8776d567dbfc4590ed6979c740c`.

The Dockerfile pins both; deployment accepts only an ACR image digest. The cloud
build script targets Linux/amd64. ACR image build/publication and Container Apps
execution were verified on 2026-11-07; no local runtime/SDK installation was
performed. Recheck support/patches and rebuild
before an operational deployment if these pins become stale.

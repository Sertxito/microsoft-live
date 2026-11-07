# Demo 01: deterministic local tutorial search

## Prerequisites

- .NET SDK 10.0.401 as pinned in `global.json`.
- No Azure account, model, credentials, or Docker daemon is required.

Run the operation-specific check without installing tools:

```powershell
pwsh -NoProfile -File scripts\setup-check.ps1 -Mode LocalDeterministic
```

## Search

After restoring/building the solution in an approved environment, run:

```powershell
dotnet run --no-build --project src\Harness.Api -- search "Azure AI Search"
```

The command uses the local synthetic catalog and returns a correlation ID,
source-bearing results, and `generatedAnswer: null`. Use a query of 3-200
characters. No tutorial content is sent to a remote service.

The protected HTTP host requires `HARNESS_AUTHORITY` and
`HARNESS_AUTH_AUDIENCE`; do not disable authentication to make a local API call.

## Protected HTTP demonstration without Azure or MCPEE

From the repository root in PowerShell:

```powershell
dotnet build Harness.sln --no-restore
pwsh -NoProfile -File scripts\demo-local.ps1 -Query "container apps"
```

This runnable demonstration exercises the actual ASP.NET HTTP pipeline with
an in-process test server and ephemeral RSA-signed JWTs from an exclusive test
issuer. No test authentication is included in the production API. It is not a
publicly listening API deployment and does not leave a background service.

Expected sequence: liveness 200, anonymous capabilities 401, authorized readiness
200, search 200 returning `tutorial-001`, source, score, duration, correlation ID
and `generatedAnswer: null`. Source URLs under `example.invalid` intentionally
identify synthetic documents, not real published tutorials.

Omit `-Query` for interactive queries; an empty line exits. Try `github copilot`,
`microsoft foundry` and `zzzznonexistent`. Invalid input returns 400. More than
30 calls per minute can return 429; wait for the next window.

Seed only to an explicit local destination:

```powershell
pwsh -NoProfile -File scripts\seed-knowledge.ps1 -Destination "$PWD\.local\catalog.json"
```

Repeated seeding merges stable IDs without duplicates; the catalog cannot exceed
20 documents. The script does not support UNC shares or Azure upload.

Run all local checks with TRX evidence:

```powershell
pwsh -NoProfile -File scripts\validate-local.ps1
```

These commands use already restored dependencies. On another machine the pinned
SDK and approved packages must be available; run `dotnet restore Harness.sln`
only with authorization to download dependencies. Nothing installs tools silently.

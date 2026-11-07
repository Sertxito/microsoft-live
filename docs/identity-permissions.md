# Identity and permissions

The selected live demo uses explicitly approved `HARNESS_AUTH_MODE=ApiKey`:
`X-API-Key` is checked against the configured random 256-bit secret. It has no
Entra app registration or user login; all key holders share the same search
permission. Managed identity to Search/ACR remains required and independent.
JWT configuration below stays available as the default optional path.

Production configuration uses `HARNESS_AUTHORITY` (HTTPS issuer) and
`HARNESS_AUTH_AUDIENCE` (token audience). A valid token must contain
`roles: ["Tutorials.Search"]` or the exact `Tutorials.Search` value within `scp`.
The preparation includes an Entra bootstrap script, not existing registrations.
No consumer Entra application or tenant-wide consent has been created.
The five planned resource-scoped managed-identity role assignments and scoped
operator loader roles were applied and verified for the actual deployment.

Azure search runtime uses a managed identity with **Search Index Data Reader**
on its intended search scope, plus AcrPull on the demo registry. Explicit
`HARNESS_MANAGED_IDENTITY_CLIENT_ID` selects its user-assigned identity without
falling back to developer credentials.

The separate loader managed identity receives Search Service Contributor
(schema), Search Index Data Contributor (documents) and Storage Blob Data
Contributor on the `tutorials` container only. It can be used from an explicitly
authorized Azure host. A workstation cannot impersonate it.

For loading from this workstation, explicitly select a separate CLI operator's
object ID and approve the same three scoped roles with `grant-demo-loader.ps1`.
`load-azure-knowledge.ps1` verifies the current CLI token's tenant/object ID
against that selected principal before any writes; it does not log in, change
the active subscription, acquire keys or grant itself rights. Destinations must
match the local foundation receipt; the loader does not require group/account
management reads merely to validate them. Review/revoke
temporary assignments when finished. Do not grant the runtime loader permissions.

`prepare-entra.ps1` prepares two tagged, single-tenant applications and service
principals: API v2 tokens, delegated search scope/application-only app role, and
a Postman public client using authorization code + PKCE. It creates no secret,
consent grant or app-role assignment. Existing untagged/ambiguous names are
rejected. Tagged applications are reconciled on retries after partial creation;
reserve their names for this demo only. Tenant policy can still require an
administrator's separate consent.

Provisioning requires authorized resource-group deployment/role-assignment
permissions; Entra creation requires permitted directory application writes.
Runtime/loader resource-scoped RBAC was verified for the selected API-key Azure
demo. Consumer directory creation was denied; tenant consent and a real JWT
consumer configuration are not claimed as validated. Your own account still
requires checking its permissions and role propagation.

Local tests use an unrelated test issuer and ephemeral RSA key supplied through
test-host DI. This validates JWT processing without fetching metadata or
obtaining an operational token. It does not validate Entra tenant configuration.

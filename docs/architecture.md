# Backend architecture

How the IAMasC server is built, and the order it ships in. The [concept](concept.md) says what IAMasC does; this says how the code is laid out to do it. Decisions behind it are in ADRs [0002](adr/0002-provider-contract.md), [0004](adr/0004-authentication.md), [0009](adr/0009-provider-protocol.md), and [0010](adr/0010-hosting.md).

## Components

```text
Browser ── htmx pages, /api/v1 ──►  IAMasC server (pwsh 7.4, Pode)
                                    │
                                    ├─ Web        routes, views, sign-in, CSRF, sessions
                                    ├─ Config     load + validate workspace YAML, compute desired state
                                    ├─ Store      SQLite: state, plans, runs, requests, audit, HR cache
                                    ├─ Git        write person files, commit, push when a remote exists
                                    ├─ Scheduler  Pode timers: HR sync, plan, apply what's due
                                    ├─ Secrets    SecretManagement (SecretStore by default)
                                    └─ Provider host
                                         │ JSON-RPC over stdin/stdout, one process per provider
                                         ├─► pwsh  iamasc/mock
                                         ├─► pwsh  iamasc/activedirectory   (Windows host only)
                                         └─► pwsh  iamasc/salesforce
```

The CLI (`iamasc validate`, `plan`, `apply`) uses the same Config, Store, and Provider host modules without the web layer.

## Source layout

```text
src/
  IAMasC.Core/          errors, logging, clock, ids, template rendering ({{ person.department }})
  IAMasC.Config/        YAML loading, JSON Schema validation, desired-state computation
    schemas/            JSON Schema per kind: workspace, person, policy, module, lifecycle, ...
  IAMasC.Store/         Invoke-IamQuery, migrations, repositories per table
    migrations/         0001_init.sql, 0002_...
  IAMasC.Git/           git CLI wrapper: status, commit, push, log for one file
  IAMasC.Secrets/       Get-IamSecret / Set-IamSecret over SecretManagement
  IAMasC.ProviderHost/  spawn, pool, call, and supervise provider processes
  IAMasC.ProviderSdk/   what provider authors import: the JSON-RPC loop and helpers
  IAMasC.Engine/        refresh, plan, apply, scheduling (slice 2)
  IAMasC.Web/           Pode routes and views
    views/  public/
providers/
  mock/                 provider.yaml, provider.ps1, fake app store (slice 2)
server.ps1              entry point: load server settings, start Pode
iamasc.ps1              CLI entry point
```

Each `src/` folder is a PowerShell module with its own tests under `tests/<Module>/`. Modules only call each other through exported functions, so the web layer never touches SQL and providers never touch the store.

## Configuration loading

1. `server.ps1 -Settings <path>` reads `iamasc-server.yaml` (or `IAMASC_SETTINGS`).
2. Each workspace in it has either `path:` (a local folder) or `repo:` (cloned into the data directory, with the workspaces feature). In the first slice, `path:` is enough; if the folder is a git repo, IAMasC commits there and pushes if a remote is set.
3. Every YAML file is parsed with `powershell-yaml`, converted to JSON, and checked with `Test-Json -Schema` against `IAMasC.Config/schemas`. Errors name the file, line, and field.
4. The loaded workspace is cached in memory and reloaded when files change (file watcher) or after IAMasC commits.

`iamasc validate <folder>` runs steps 3 and 4 and exits non-zero on any error, so workspace repos can run it in their own CI.

## Data store

SQLite through `Microsoft.Data.Sqlite`, with the assembly restored by `build.ps1` from NuGet at a pinned version and checked against its SHA-512. One database file per server, under the data directory. Tables arrive through numbered migrations; the first slice needs only `schema_migrations`, `audit`, `hr_cache`, and `sessions`. State, plans, runs, and requests arrive with slice 2.

All queries are parameterized. Writes go through one serialized writer, which suits SQLite's single-writer model.

## Sign-in

- **Dev mode** (`auth.mode: dev`): a fixed local user with the Admin role. The server refuses to start in dev mode unless every endpoint binds to `127.0.0.1` or `::1`, and every page shows a red "Dev mode" banner.
- **Entra ID**: OpenID Connect with Pode's Azure AD scheme. The app registration's `groups` claim maps to roles per workspace in server settings. The client secret comes from the vault.
- AD form sign-in arrives with the AD provider.
- Sessions are server-side with secure, HTTP-only, SameSite=Lax cookies. Every form posts with a CSRF token.

## Secrets

`Microsoft.PowerShell.SecretManagement` with `SecretStore` as the default vault. Any other SecretManagement vault (Azure Key Vault, HashiCorp Vault, CyberArk) can be registered instead without code changes. Secret names follow `iamasc/<workspace>/<provider>/<field>`. YAML only ever holds `{ secret: <name> }`. Secrets are never logged, never written to the database, and passed to providers only over the provider's stdin.

## Providers

### Runtime

Each provider runs in its own `pwsh` process, started by the provider host and spoken to with JSON-RPC 2.0, one JSON message per line on stdin and stdout. Stderr is captured as provider logs. The protocol is in [ADR 0009](adr/0009-provider-protocol.md).

- One process per provider per workspace, so each only holds its own workspace's credentials.
- Processes are started on first use, kept warm, and recycled after an idle timeout, a memory limit, or a crash. A crashed provider fails the calls in flight; the job retries them.
- Every call has a timeout. A provider that stops answering is killed and restarted.
- Later, the same protocol runs over a TLS connection to a **remote provider host**, so the server can live in a Linux container while the AD provider runs on a domain-joined Windows machine.

### Package layout

```text
providers/mock/
  provider.yaml      name, version, protocol, configSchema, account and permission schema
  provider.ps1       entry point: Import-Module IAMasC.ProviderSdk; Start-IamProvider @handlers
  lib/               the provider's own code
```

A provider author writes ordinary PowerShell functions and hands them to `Start-IamProvider`, which runs the message loop, validates inputs against the schema, and turns exceptions into protocol errors.

### Configuration schema

`provider.yaml` carries a JSON Schema for its settings. A few `x-iamasc-*` keywords tell the UI how to draw the form.

```yaml
configSchema:
  type: object
  required: [server, domain, credential]
  properties:
    domain:
      type: string
      title: Domain
      examples: [corp.example.com]
    server:
      type: string
      title: Domain controller
      description: Leave empty to locate one automatically.
    credential:
      type: object
      title: Service account
      x-iamasc-secret: credential          # stored in the vault, never in YAML
    scope:
      type: object
      title: What this workspace may manage
      properties:
        ous: { type: array, items: { type: string }, x-iamasc-widget: dn-picker }
        groupPrefixes: { type: array, items: { type: string } }
```

### Adding a provider

The same steps run from the UI wizard or from files and the CLI.

| Step | UI | Files and CLI |
| --- | --- | --- |
| 1. Choose | Pick from the registry list (slice 2: bundled providers only) | Add it to `requiredProviders` in `iamasc.yaml` |
| 2. Configure | Form generated from `configSchema` | Add the provider block in `iamasc.yaml` |
| 3. Secrets | Secret fields go straight to the vault | `iamasc secret set iamasc/corp-chicago/activedirectory/credential` |
| 4. Test | Starts the provider with the draft settings and calls `testConnection`; shows what it can see (for AD: domain, OUs in scope, group count) | `iamasc provider test activedirectory` |
| 5. Save | Writes the `iamasc.yaml` change: a commit or pull request per the workspace's git setting, or a plain file write with no git | Commit the file yourself |
| 6. Install | Downloads and verifies the package, updates `.iamasc.lock.yaml` | `iamasc init` |
| 7. Adopt | Offers `import` to link existing accounts to people | `iamasc import activedirectory` |

Nothing is written to an application until the first plan is applied, and new workspaces start in dry run.

### The mock provider

`iamasc/mock` ships with IAMasC so the whole provider flow can be tested anywhere, including CI. It keeps a fake application in a JSON file and has one permission type of each shape:

| Permission | Shape | Example values |
| --- | --- | --- |
| `plan` | `single` | Free, Pro, Enterprise |
| `group` | `set` | Everyone, Finance, Admins |
| `projectRole` | `scoped` | Viewer or Editor on project Apollo |
| `tableGrant` | `matrix` | SELECT, INSERT on ledger, payroll |
| `title` | `attribute` | any string |

Its config has knobs for testing failure: added latency, a failure rate, and a list of usernames that always fail, so retries, timeouts, and partial applies get exercised.

## Hosting

Both from the same code and the same release zip ([ADR 0010](adr/0010-hosting.md)):

- **Windows service**: a release ships a WinSW service wrapper (pinned version, hash-checked) and `Install-IAMasCService.ps1`, which registers the service under a dedicated account (a gMSA where available).
- **Linux container**: built from the official PowerShell image pinned by digest, running as a non-root user, with `/data` (database, workspace clones) and `/config` (server settings) as volumes. Release builds scan the image with Trivy and sign it.

## Delivery plan

Each line is one feature branch and one pull request into `main`.

**Slice 1: IAMasC without providers**

1. `feature/config-engine`: `IAMasC.Config` with JSON Schemas for every kind, `iamasc validate`, `examples/` validated in CI.
2. `feature/store`: `IAMasC.Store` with SQLite, migrations, and the audit log.
3. `feature/web-shell`: Pode server, layout from the mockups, dev mode, `/health`, dashboard and people pages read from person files.
4. `feature/new-hire`: new-hire and offboard forms write person files, with git commit when the folder is a repo.
5. `feature/entra-signin`: Entra ID sign-in and role mapping.
6. `feature/packaging`: Windows service wrapper and container image in the release pipeline.

**Slice 2: the first provider**

1. `feature/provider-host`: protocol, `IAMasC.ProviderHost`, `IAMasC.ProviderSdk`, and a protocol test kit any provider can run.
2. `feature/mock-provider`: `iamasc/mock` with every shape and failure knobs.
3. `feature/add-provider`: the wizard, vault integration, and connection test.
4. `feature/plan`: refresh and plan against the mock, plan pages.
5. `feature/apply`: saved plans, jobs, retries, scheduling.

After slice 2: the Active Directory provider (with AD sign-in), HR sources, approvals and notifications, multiple workspaces, the registry.

# 0009: Providers run out of process and speak JSON-RPC

- Status: Accepted
- Date: 2026-10-21

## Context

Providers run with privileged credentials, use modules that only exist on some platforms (the `ActiveDirectory` module is Windows-only), and may come from third parties through the registry. Loading them into the server's runspaces would let one provider crash or slow the server, read another provider's credentials, or force the server onto Windows.

## Decision

Each provider runs as its own `pwsh` process, one per provider per workspace, started and supervised by the provider host. They talk JSON-RPC 2.0, one JSON message per line, over the process's stdin and stdout. Stderr carries logs.

Methods the core calls:

| Method | Purpose |
| --- | --- |
| `initialize` | Exchange protocol versions and capabilities. The core refuses a provider outside its supported range. |
| `getSchema` | Account, permission, and config schema (the same content as `provider.yaml`) |
| `configure` | Send settings with secrets resolved from the vault. Sent once per process start. |
| `testConnection` | Check settings and report what the provider can see |
| `getCatalog` | List grantable values for a permission type, paged |
| `readAccount`, `readPermissions` | Live state for one identity |
| `listAccounts` | Paged list of all accounts in scope, for import and orphan detection |
| `planChange` | Turn desired vs. live into ordered, concrete changes |
| `applyChange` | Execute one change idempotently and return the new state |
| `shutdown` | Finish in-flight work and exit |

The provider can send `log` and `progress` notifications at any time. Every request has a timeout set by the core; a provider that misses it is killed and restarted, and the job that made the call retries it.

Provider authors don't write the message loop. `IAMasC.ProviderSdk` provides `Start-IamProvider`, which takes a hashtable of handler script blocks, validates inputs against the schema, and converts exceptions to protocol errors. A protocol test kit runs every provider through the same Pester suite.

## Consequences

- A provider crash, hang, or memory leak stays in its own process.
- The server can run on Linux while Windows-only providers run elsewhere: the same protocol runs over TLS to a remote provider host (a later feature).
- Secrets reach a provider only through `configure` on stdin, never through arguments or environment variables.
- Each call costs a message round trip. Processes are kept warm, so the ~0.5s pwsh start cost is paid once per process, not per call.
- This supersedes the in-process module contract in ADR 0002. The function names there become method names here.

## Alternatives considered

- In-process PowerShell modules: simplest, but no isolation, and the server would have to run where every provider can run.
- gRPC, as Terraform uses: typed and fast, but needs generated code and a .NET dependency in every provider. JSON-RPC over stdio needs nothing beyond pwsh and stays readable when debugging.
- HTTP servers per provider: workable, but needs port management and authentication on every provider for no gain over stdio locally.

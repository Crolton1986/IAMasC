# 0001: PowerShell 7 and Pode

- Status: Accepted
- Date: 2026-10-21

## Context

IAMasC drives Active Directory first and other Microsoft systems later. The people who run and extend it are Windows and identity administrators who already write PowerShell. It needs a web UI, an API, and background scheduling.

## Decision

Write IAMasC in PowerShell 7.4+ and serve it with Pode, which provides HTTP endpoints, view rendering, authentication, sessions, timers, and schedules in one module.

## Consequences

- The `ActiveDirectory`, `Microsoft.Graph`, and `SecretManagement` modules are used directly, no wrappers.
- Admins can read and modify connectors without learning another language.
- Pode runs routes in separate runspaces. Shared state goes through Pode state or the database, and modules are imported per runspace.
- PowerShell 7 runs on Linux, so a container build stays possible once AD access moves to LDAP.
- CodeQL has no PowerShell support. Static analysis relies on PSScriptAnalyzer with InjectionHunter, plus AI review.

## Alternatives considered

- ASP.NET Core in C#: stronger typing and tooling, but a second language between the UI and every AD and Graph call, and a smaller pool of contributors among admins.
- Python (FastAPI): good web stack, weak AD story on Windows.
- PowerShell Universal: capable, but commercially licensed, which doesn't fit an open-source project.

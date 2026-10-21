# 0003: State and audit backend, SQLite first

- Status: Accepted
- Date: 2026-10-21

## Context

IAMasC stores state, saved plans, job history, an HR cache, and the execution audit log. Small deployments want a single file and no database server. Larger ones will require SQL Server for backups, HA, and reporting.

## Decision

All data access goes through `Invoke-IamQuery` and `Invoke-IamNonQuery` with named parameters. A backend implements them: SQLite first, SQL Server later. Schema changes are numbered SQL migration files tracked in a `schema_migrations` table. Migrations use SQL both engines accept; where they differ, a migration can ship a per-backend variant.

## Consequences

- Parameterized queries everywhere, no string-built SQL.
- Switching backends is a config change plus a data copy tool.
- SQLite allows one writer at a time. The job runner is the main writer, which suits that limit at the expected scale (hundreds to low thousands of identities).

## Alternatives considered

- An ORM: none mature in PowerShell.
- SQL Server only: too heavy for a first install and for CI.

# 0002: Providers with a published permission schema

- Status: Accepted. Runtime and function list superseded by [0009](0009-provider-protocol.md).
- Date: 2026-10-21

## Context

Every application models access differently: AD group membership, a Salesforce profile plus permission sets plus a license, GitHub teams with a role per team, SQL privileges on objects, Azure roles at a scope. If the core knows about any of these, adding the next application means changing the core, and the UI ends up with one hand-built page per application.

## Decision

Each application is a **provider**: a versioned package with a `provider.yaml` manifest and PowerShell code. The manifest declares the protocol version, the account attributes, and each permission type with a **shape** the core understands: `single`, `set`, `scoped`, `matrix`, or `attribute`. Validation, planning, state, and the UI are all driven by that schema.

A provider exports a fixed set of functions:

| Function | Purpose |
| --- | --- |
| `Get-Schema` | Return the manifest's account and permission schema |
| `Get-Catalog` | List what can be granted (groups, roles, licenses) |
| `Read-Account`, `Read-Permissions` | Read live state for one identity |
| `Plan-Change` | Turn a desired-vs-live diff into concrete, ordered changes |
| `Invoke-Change` | Execute one change, idempotently, returning the new external state |
| `Import-Account` | Adopt an existing account into state |

Every write supports `-WhatIf`. Expected failures are returned, not thrown.

## Consequences

- A new application is a new provider package. The core and the UI don't change.
- The UI renders a person's access per provider from the schema shapes, so an AD group list and a SQL privilege grid come from the same code.
- A Pester contract suite runs against every provider, including a mock provider that implements every shape.
- An LDAP-based AD provider can replace the module-based one without touching configuration beyond the provider source.
- No compile-time interface checking. The contract tests carry that weight.

## Alternatives considered

- A fixed connector contract with "account" and "group" only: simple, but every non-AD system would be forced into the group shape, and the UI would mislead.
- PowerShell classes for providers: classes in modules don't reload cleanly and type identity breaks across Pode runspaces.
- Out-of-process providers over gRPC, as Terraform does: the right long-term isolation, but too much machinery for a first version. The protocol version field leaves room to add it.

# 0002: Connectors as modules with a fixed function contract

- Status: Accepted
- Date: 2026-10-21

## Context

IAMasC will talk to many systems: AD, Entra ID, HR platforms, inventory tools. Each new system must not require changes to the lifecycle engine, and the AD implementation must be replaceable (module now, LDAP later).

## Decision

Each connector is a PowerShell module in `src/Connectors/<Kind>.<Name>/` with a `connector.psd1` manifest (name, kind, version, capabilities, config schema) and exported functions with fixed names per kind (see the concept document). The core loads connectors by manifest and calls them by module-qualified name. Every write function supports `-WhatIf` and returns a result hashtable instead of throwing for expected failures.

## Consequences

- New connectors don't touch the core. A Pester contract test suite runs against every connector, including the mock.
- Two AD connectors can coexist and be switched in config.
- No compile-time interface checking. The contract tests carry that weight.

## Alternatives considered

- PowerShell classes implementing a base class: classes defined in modules don't reload cleanly and type identity breaks across Pode runspaces.
- Out-of-process plugins over HTTP: more isolation, much more operational work for a first version.

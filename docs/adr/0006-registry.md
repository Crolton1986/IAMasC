# 0006: Registry for providers and modules

- Status: Proposed
- Date: 2026-10-21

## Context

Providers and modules should be shareable across organizations, like the Terraform Registry. A provider runs with privileged credentials, so installing one is a supply-chain decision.

## Decision

- A registry is an index (`index.json`) listing packages, versions, download URLs, SHA-256 hashes, and signatures. The public registry is a git repository maintained by this project. A private registry can be any git repository or file share with the same index format.
- Package addresses are `<namespace>/<name>`, for example `iamasc/activedirectory` or `corp/finance-analyst`. Versions follow SemVer; constraints use `~>`, `>=`, and exact pins.
- `iamasc init` resolves constraints and writes `.iamasc.lock.yaml` with the exact version and hash of every package. Later runs refuse a package whose hash doesn't match.
- Packages are signed with Sigstore (keyless, tied to the publishing GitHub workflow). Verification is on by default and can only be turned off per namespace in `iamasc.yaml`.
- A provider declares the protocol version it implements. The core refuses providers outside the range it supports.

## Consequences

- Upgrading a provider is a lock-file change in a pull request, so it passes the same gates as code.
- The project needs a publishing workflow and an index repository before third parties can publish.
- Offline and air-gapped installs work with a private registry on a file share.

## Alternatives considered

- PSGallery alone: no lock files, no signature policy, and typosquatting has happened there. Packages may still be mirrored there for discovery.
- Copying provider folders by hand: no versioning or integrity checks.

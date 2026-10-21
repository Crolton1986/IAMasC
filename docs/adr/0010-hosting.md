# 0010: Ship as a Windows service and a Linux container

- Status: Accepted
- Date: 2026-10-21

## Context

AD-heavy companies run Windows servers and expect a Windows service. Others run containers. Pode has no built-in Windows service support, and `pwsh.exe` can't register itself as a service.

## Decision

Build both from the same code in every release:

- **Windows service**: the release includes a pinned, hash-checked [WinSW](https://github.com/winsw/winsw) wrapper and `Install-IAMasCService.ps1`, which registers IAMasC as a service running under a dedicated account (a group managed service account where available), with logs under the data directory and automatic restart on failure.
- **Linux container**: an image built from the official PowerShell image pinned by digest, running as a non-root user, with `/data` and `/config` volumes and a `HEALTHCHECK` on `/health`. Release builds scan it with Trivy, sign it with cosign, and publish it to GHCR.

Windows-only providers run on Windows hosts. The container runs them through a remote provider host (ADR 0009) once that feature exists.

## Consequences

- CI keeps testing both platforms, as it does today.
- The deploy workflow's Windows path (self-hosted runner, release zip, health check, rollback) stays as written. A container deploy path is added with the image.
- WinSW is a third-party binary in the release. It's pinned by version and hash, and listed in the SBOM.

## Alternatives considered

- Windows only: matches the AD start, but blocks container users and the move away from Windows the concept plans for.
- A scheduled task at startup instead of a service: no recovery handling and poor visibility to admins.
- A custom .NET service host: no third-party binary, but more code to maintain than WinSW's configuration file.

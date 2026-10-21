# Security policy

IAMasC holds privileged credentials and changes who can access what. Treat bugs in it accordingly.

## Reporting a vulnerability

Report privately through [GitHub security advisories](https://github.com/Crolton1986/IAMasC/security/advisories/new). Don't open a public issue or PR.

Include what's affected, how to reproduce it, and the impact you expect. You'll get an acknowledgement within 5 business days and a fix or plan within 30 days for confirmed issues.

## Supported versions

Until 1.0, only the latest release gets security fixes.

## How the project guards itself

- Every PR runs secret scanning, vulnerability scanning, CodeQL, workflow auditing, dependency review, PowerShell injection linting, and an AI security review of the diff. See CONTRIBUTING.md.
- GitHub Actions are pinned to commit SHAs, and tool binaries downloaded in CI are checksum-verified.
- Releases ship with an SPDX SBOM and a signed build provenance attestation. Verify a download with:

  ```sh
  gh attestation verify IAMasC-x.y.z.zip --repo Crolton1986/IAMasC
  ```

## Maintainer setup for the AI security review

The `security-review` job uses [anthropics/claude-code-security-review](https://github.com/anthropics/claude-code-security-review). Add an Anthropic API key as the `ANTHROPIC_API_KEY` repository secret. Without it the job passes with a warning so forks and new clones aren't blocked. The reviewer isn't hardened against prompt injection, so it never runs on PRs from forks; a maintainer reviews those by hand.

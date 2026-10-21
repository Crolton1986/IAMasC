# Contributing

Thanks for helping. IAMasC creates and removes real accounts, so the process is strict on purpose.

## Workflow

1. Open an issue (or pick one) so the change is agreed before code is written. New features start with a concept or mockup in the issue.
2. Branch from `main`:

   | Prefix | Use for |
   | --- | --- |
   | `feature/<issue>-<name>` | New capability |
   | `fix/<issue>-<name>` | Bug fix |
   | `security/<issue>-<name>` | Security fix (coordinate privately first, see SECURITY.md) |
   | `docs/<name>` | Documentation only |
   | `chore/<name>` | Tooling, CI, dependency bumps |

3. Commit with [Conventional Commits](https://www.conventionalcommits.org/): `feat(ad): provision account disabled until start date`.
4. Run the same checks CI runs:

   ```powershell
   ./build.ps1 -Task Bootstrap   # once
   ./build.ps1 -Task Lint, Test, SecurityScan
   ```

5. Open a PR into `main` and fill in the template. One feature or fix per PR.
6. Every gate must pass and a code owner must approve. `main` only accepts squash merges.

`main` is always releasable. Nobody pushes to it directly.

## Gates on every PR

| Check | What it does |
| --- | --- |
| `lint` | PSScriptAnalyzer with repo rules plus InjectionHunter code-injection rules |
| `test (ubuntu)`, `test (windows)` | Pester on both platforms |
| `docs` | markdownlint and local link check |
| `secrets-scan` | gitleaks over full history |
| `vuln-scan` | Trivy (vulnerable deps, misconfig, secrets) and the PowerShell module audit |
| `sast` | CodeQL |
| `workflow-audit` | actionlint and zizmor on GitHub Actions workflows |
| `dependency-review` | Blocks new dependencies with known vulnerabilities or disallowed licenses |
| `security-review` | AI security review of the diff (PRs from this repo only) |

Findings from the SARIF-producing tools also appear under the repo's **Security → Code scanning** tab.

## Rules that the tests enforce

- Every GitHub Action is pinned to a full commit SHA with the version in a comment. Use the commit the tag points to, not the tag object: `git ls-remote https://github.com/OWNER/REPO "refs/tags/vX.Y.Z^{}"` (zizmor flags the difference).
- Every workflow declares `permissions:` and jobs ask only for what they use.
- No `pull_request_target`.
- Every PowerShell module in `requirements.psd1` is pinned to an exact version.

## Dependencies

Adding a PowerShell module means adding it to `requirements.psd1` with an exact version, saying why in the PR, and checking its publisher and download history on PSGallery. PSGallery isn't covered by GitHub's advisory database, so `security/module-denylist.psd1` is where known-bad modules go.

## Design decisions

Anything that changes the architecture, a connector contract, the data model, or the security model gets an ADR in `docs/adr/` (copy `0000-template.md`).

## Releases

1. Move the **Unreleased** entries in `CHANGELOG.md` to a new version heading in a `chore/release-x.y.z` PR.
2. After it merges, tag `main`: `git tag -s vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z`.
3. The `release` workflow re-runs every gate, packages the zip, generates an SBOM and provenance attestation, and publishes the GitHub release.
4. The `deploy` workflow ships it to staging, then waits for approval before production.

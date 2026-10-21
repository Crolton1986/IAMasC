# IAMasC

Identity and access lifecycle tracking, from hire to offboard.

IAMasC records every person the business hires, every account and permission they get in each application, and every change until they leave. It takes hire and termination data from HR (manual entry, CSV, ADP), provisions and deprovisions accounts through per-application connectors, and keeps an audit trail of who got what, when, and why.

Built on PowerShell 7 and [Pode](https://github.com/Badgerati/Pode). Active Directory is the first connector.

## Status

Stage 0: repo foundation, CI/CD, concept, and mockups. No application code yet.

## How work gets shipped

Every change goes through a feature branch and a pull request into `main`. A PR merges only when lint, tests on Ubuntu and Windows, secret scanning, vulnerability scanning, CodeQL, workflow auditing, dependency review, and an AI security review all pass, and a code owner approves. Tagged releases are packaged with an SBOM and a signed provenance attestation, then deployed to staging and, after approval, production.

- [CONTRIBUTING.md](CONTRIBUTING.md): branch naming, commits, the full list of gates
- [SECURITY.md](SECURITY.md): reporting vulnerabilities, verifying releases
- [docs/repository-settings.md](docs/repository-settings.md): GitHub settings and the `main` ruleset

## Running the checks locally

Requires PowerShell 7.4 or later.

```powershell
./build.ps1 -Task Bootstrap                    # install pinned modules once
./build.ps1 -Task Lint, Test, SecurityScan     # what CI runs
```

`SecurityScan` also runs `gitleaks` and `trivy` when they're on your PATH.

# IAMasC

Identity and access management as code.

Declare in YAML who should have what access, and IAMasC keeps every application in line with it, from the day HR records a hire to the day the last account is deleted. It works like Terraform: HR data and policies produce a desired state, IAMasC diffs it against what each application really has, shows a plan, and applies it through providers. Providers and reusable modules come from a registry, and a web UI sits on top for HR, IT, and auditors.

Built on PowerShell 7 and [Pode](https://github.com/Badgerati/Pode). Active Directory is the first provider. See [docs/concept.md](docs/concept.md) and the sample configuration in [examples/corp-chicago](examples/corp-chicago).

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

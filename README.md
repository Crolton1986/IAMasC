# IAMasC

Identity and access management as code.

Declare in YAML who should have what access, and IAMasC keeps every application in line with it, from the day HR records a hire to the day the last account is deleted. It works like Terraform: HR data and policies produce a desired state, IAMasC diffs it against what each application really has, shows a plan, and applies it through providers. Providers and reusable modules come from a registry, and a web UI sits on top for HR, IT, and auditors.

Built on PowerShell 7 and [Pode](https://github.com/Badgerati/Pode). Active Directory is the first provider. See [docs/concept.md](docs/concept.md) and the sample configuration in [examples/corp-chicago](examples/corp-chicago).

## Status

Slice 1 in progress: the config engine (`iamasc validate`), the SQLite store, and a read-only web UI are in. Next: new-hire and offboard forms. See [docs/architecture.md](docs/architecture.md).

## How work gets shipped

Every change goes through a feature branch and a pull request into `main`. A PR merges only when lint, tests on Ubuntu and Windows, secret scanning, vulnerability scanning, CodeQL, workflow auditing, dependency review, and an AI security review all pass, and a code owner approves. Tagged releases are packaged with an SBOM and a signed provenance attestation, then deployed to staging and, after approval, production.

- [CONTRIBUTING.md](CONTRIBUTING.md): branch naming, commits, the full list of gates
- [SECURITY.md](SECURITY.md): reporting vulnerabilities, verifying releases
- [docs/repository-settings.md](docs/repository-settings.md): GitHub settings and the `main` ruleset

## Run it locally

```powershell
./build.ps1 -Task Bootstrap                          # once
./server.ps1 -Settings ./examples/server/dev.yaml
```

Open <http://127.0.0.1:8080>. Dev mode signs you in as a local admin and only listens on loopback. The example workspace's people show up on the dashboard and the people page; there are no providers yet, so the access section of each person is empty. Data and logs go to `out/dev-data`.

## Validate a workspace

```powershell
./build.ps1 -Task Bootstrap                          # once: pinned modules, plus SQLite assemblies into lib/
./iamasc.ps1 validate ./examples/corp-chicago        # a workspace folder
./iamasc.ps1 validate ./examples/server/iamasc-server.yaml -Format json
```

`validate` checks every file against the schema for its kind (`src/IAMasC.Config/schemas`), then checks that the files agree: providers are declared, modules resolve and match their version constraints, approval rules and notification routes point at things that exist, person files are named after the person, and no secret is written in plain text. It exits 1 on any error, or on warnings too with `-Strict`, so a workspace repo can run it in its own CI.

## Running the checks locally

Requires PowerShell 7.4 or later.

```powershell
./build.ps1 -Task Bootstrap                    # install pinned modules once
./build.ps1 -Task Lint, Test, SecurityScan     # what CI runs
```

`SecurityScan` also runs `gitleaks` and `trivy` when they're on your PATH.

## License

[Apache License 2.0](LICENSE).

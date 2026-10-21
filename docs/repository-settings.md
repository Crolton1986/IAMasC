# Repository settings

Some protections live in GitHub settings, not in files. Apply these once, in this order.

## 1. Make the repository public

Settings → General → Danger Zone → Change visibility → Public.

Before you do, confirm the `secrets-scan` job is green on `main` (it scans full history). CodeQL, code scanning uploads, dependency review, secret scanning, and rulesets are free on public repositories, and several gates depend on them.

## 2. Security features

Settings → Advanced Security (or Code security):

- Dependency graph: on
- Dependabot alerts and security updates: on
- Secret scanning and push protection: on
- Private vulnerability reporting: on (SECURITY.md points reporters here)
- Code scanning: leave the default setup off. The `sast` job runs CodeQL as an advanced setup.

## 3. Actions

Settings → Actions → General:

- Actions permissions: allow actions created by GitHub and select non-GitHub actions. Allow list:
  `DavidAnson/markdownlint-cli2-action@*, lycheeverse/lychee-action@*, anchore/sbom-action@*, anthropics/claude-code-security-review@*`
- Require actions to be pinned to a full-length commit SHA: on
- Fork pull request workflows from outside collaborators: require approval for all outside collaborators
- Workflow permissions: read repository contents. Leave "Allow GitHub Actions to create and approve pull requests" off.

## 4. Pull requests

Settings → General → Pull Requests: allow squash merging only, default the message to the PR title and description, and turn on "Automatically delete head branches".

## 5. Ruleset for `main`

Apply after the first PR has run every workflow, so GitHub recognizes each check name.

With the GitHub CLI:

```sh
gh api --method POST repos/Crolton1986/IAMasC/rulesets --input .github/rulesets/main.json
```

Or Settings → Rules → Rulesets → New ruleset → Import a ruleset, and pick `.github/rulesets/main.json`.

The ruleset blocks direct pushes and force pushes, requires a squash-merged PR with one code-owner approval (re-approved after new pushes), requires resolved conversations, and requires every CI and security check to pass on an up-to-date branch. It also blocks merges while CodeQL reports high or critical alerts.

As the only maintainer you can't approve your own PR. Until there's a second maintainer, either add yourself as a bypass actor for pull requests only (Settings → Rules → main → Bypass list → Repository admin, "For pull requests only") or set the required approvals to 0. Every automated gate still applies either way.

## 6. Secrets and variables

| Name | Kind | Purpose |
| --- | --- | --- |
| `ANTHROPIC_API_KEY` | Secret | AI security review on PRs |
| `DEPLOY_ENABLED` | Variable | `true` turns on the deploy workflow |
| `INSTALL_ROOT`, `SERVICE_NAME` | Variables | Where and how the deploy script installs |
| `STAGING_URL`, `PRODUCTION_URL` | Variables | Health check targets |

## 7. Environments

Settings → Environments: create `staging` and `production`. On `production`, add yourself as a required reviewer and restrict deployments to tags matching `v*`.

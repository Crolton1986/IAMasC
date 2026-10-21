# IAMasC concept

IAMasC is identity and access management as code. You declare in YAML who should have what access, IAMasC compares that with what each application really has, shows you a plan, and applies it. It works the way Terraform does for infrastructure: configuration, providers, modules, a registry, state, `plan`, and `apply`. A web UI sits on top for HR, IT, and auditors who'll never open a YAML file.

This document is the long-term shape. Each feature that ships should fit it; when one doesn't, change this document in the same PR.

Clickable mockups: [docs/mockups/index.html](mockups/index.html) (open it in a browser). Example configuration: [examples/corp](../examples/corp).

## The Terraform mapping

| Terraform | IAMasC | Example |
| --- | --- | --- |
| `.tf` files | YAML configuration in a git repo | `policies/finance.yaml` |
| Provider | Plugin for one application, declaring its account and permission types | `iamasc/activedirectory`, `iamasc/salesforce` |
| Resource | An account or a permission grant in an application | an AD group membership |
| Data source | Read-only input, mainly HR | `iamasc/adp` workers |
| Module | Reusable, versioned bundle of grants with inputs | `corp/finance-analyst` |
| Registry | Index of published providers and modules | `registry.iamasc.dev` or a private one |
| `.terraform.lock.hcl` | `.iamasc.lock.yaml` with versions and SHA-256 hashes | |
| State | What IAMasC created or adopted, with external IDs | `E-004127 / activedirectory.account → objectGUID` |
| `plan` / `apply` | Diff desired vs. state vs. live, then execute | `iamasc plan`, `iamasc apply` |
| `import` | Adopt accounts and grants that already exist | existing AD users on day one |
| Drift | Live differs from state | a group added by hand in ADUC |

## Where truth lives

- **HR is the source of truth for who exists** and their attributes (department, title, manager, location, dates). It's a data source, not YAML. Nobody writes a YAML file per new hire.
- **Git is the source of truth for who should have what**: policies, modules, lifecycle rules, and per-person exceptions. Every change to access is a diff someone can review.
- **State is IAMasC's record of what it manages** in each application. It lives in the database backend (SQLite now, SQL Server later), versioned with a serial number, locked during apply.
- **Live is what the application says right now.** A refresh reads it.

The desired state for a person is computed: HR attributes go through policies and modules, then per-person exceptions are added. A new hire in ADP produces a plan with no YAML change. A new policy produces a plan for everyone it matches.

## Configuration

Every file is a YAML document with `apiVersion` and `kind`, so the format can evolve without breaking old files. `iamasc validate` checks every document against JSON Schema, including the schemas providers publish.

```yaml
# iamasc.yaml: root settings and required providers
apiVersion: iamasc.dev/v1
kind: Workspace
metadata:
  name: corp
spec:
  requiredProviders:
    activedirectory: { source: iamasc/activedirectory, version: "~> 1.0" }
    salesforce:      { source: iamasc/salesforce,      version: "~> 0.3" }
    adp:             { source: iamasc/adp,             version: "~> 1.0" }
  backend:
    sqlite: { path: data/state.db }
```

```yaml
# policies/finance.yaml: everyone in Finance gets this
apiVersion: iamasc.dev/v1
kind: Policy
metadata:
  name: finance
spec:
  match:
    department: Finance
  use:
    - module: corp/finance-analyst
      version: "1.2.0"
      with:
        costCenter: "{{ person.costCenter }}"
```

```yaml
# modules/finance-analyst/module.yaml: one role, many applications
apiVersion: iamasc.dev/v1
kind: Module
metadata:
  name: finance-analyst
  version: 1.2.0
spec:
  inputs:
    costCenter: { type: string, required: true }
  grants:
    activedirectory:
      account: { ou: "OU=Finance,OU=Users,DC=corp,DC=example,DC=com" }
      group: [GG-Finance-All, GG-SharePoint-Finance]
    salesforce:
      account: { license: Salesforce }
      profile: Finance User
      permissionSet: [Reports_Viewer]
```

```yaml
# identities/E-004127.yaml: an exception for one person, with an owner, a ticket, and an expiry
apiVersion: iamasc.dev/v1
kind: Grant
metadata:
  name: okafor-netsuite-approver
spec:
  identity: E-004127
  reason: Quarter-end approvals
  ticket: CHG-20931
  approvedBy: E-001104
  expires: 2026-12-31
  grants:
    netsuite:
      role: [Approver]
```

```yaml
# lifecycle.yaml: what each HR status means for every account
apiVersion: iamasc.dev/v1
kind: Lifecycle
spec:
  preProvisionDays: 3
  states:
    Pending:     { account: disabled, grants: apply }
    Active:      { account: enabled,  grants: apply }
    Offboarding: { account: disabled, grants: revoke, snapshot: true }
    Terminated:  { account: absent,   after: 90d }
  approvals:
    autoApply: [joiner, mover, leaver]   # HR-driven changes go straight through
    requireApproval: [exception, privileged]
```

Joiner, mover, and leaver stop being special code paths. They're changes in HR attributes that change the computed desired state. Offboarding is a plan like any other: `~ disable account`, `- remove 6 groups`.

## Providers and the permission model

Applications grant access in very different shapes. AD has group membership. Salesforce has one profile, many permission sets, and a license. GitHub has an org role and team membership with a role per team. A database has privileges on objects. Azure has a role at a scope. The core can't hard-code any of these.

Each provider publishes a **schema** describing its account and each permission type, and IAMasC's validation, plan, state, and UI are all driven by it.

```yaml
# provider.yaml shipped inside iamasc/salesforce
apiVersion: iamasc.dev/v1
kind: Provider
metadata:
  name: salesforce
  version: 0.3.1
spec:
  protocol: 1
  account:
    key: Id
    attributes:
      username: { type: string }
      license:  { type: enum, source: catalog }
  permissions:
    profile:
      shape: single        # exactly one per account
      source: catalog
    permissionSet:
      shape: set           # any number
      source: catalog
    permissionSetLicense:
      shape: set
      countable: true      # seats, shown with used/available
```

The shapes the core understands, and how the UI renders each:

| Shape | Meaning | Example | UI |
| --- | --- | --- | --- |
| `single` | Exactly one value | Salesforce profile, M365 license plan | A labeled value |
| `set` | Any number of values from a catalog | AD groups, Salesforce permission sets | A list with origin and dates |
| `scoped` | A value at a scope | Azure role at subscription, GitHub team with role | A table of scope and role |
| `matrix` | Privileges on objects | SQL `SELECT` on `finance.ledger` | An object × privilege grid |
| `attribute` | A plain account property | AD `title`, `manager` | Shown under the account |

A provider implements a fixed set of functions over that schema: `Get-Schema`, `Get-Catalog`, `Read-Account`, `Read-Permissions`, `Plan-Change`, `Invoke-Change`, `Import-Account`. The core never knows what a "group" is. See [ADR 0002](adr/0002-provider-contract.md).

## Registry and modules

Providers and modules are versioned packages listed in a registry. The public registry is a git repository with an index file; organizations can run a private one (a folder share or an internal git repo) for their own modules.

- `iamasc init` resolves version constraints, downloads packages, verifies their SHA-256 hashes and signatures, and writes `.iamasc.lock.yaml`.
- Upgrades only happen on `iamasc init -upgrade`, through a PR that changes the lock file, so they pass the same review and security gates as code.
- Providers declare the protocol version they speak, so the core can refuse an incompatible one with a clear message.
- PowerShell modules are the package format underneath, so providers can still be written by anyone who knows PowerShell.

See [ADR 0006](adr/0006-registry.md).

## Plan and apply

```text
$ iamasc plan
Refreshing state... 412 identities, 2 providers

  # identity E-004611 (Grace Lindqvist), joiner from adp
  + activedirectory.account  glindqvist  (disabled, OU=HR,OU=Users)
  + activedirectory.group    GG-AllStaff, GG-Chicago, GG-HR-All, GG-Workday-Readers

  # identity E-004127 (Maria Okafor), department Finance -> Treasury
  - activedirectory.group    GG-SharePoint-Finance
  + activedirectory.group    GG-Treasury-All
  ~ salesforce.profile       Finance User -> Treasury User

  # identity E-003318 (Dan Whitfield), leaver at 2026-10-23 17:00
  ~ activedirectory.account  dwhitfield  enabled -> disabled, move to OU=Disabled Users
  - activedirectory.group    6 groups (snapshot saved)
  - salesforce.account       deactivate, free 1 Salesforce license

Plan: 7 to add, 3 to change, 9 to remove. 2 changes need approval.
```

- A plan is saved and applied exactly as shown, never recomputed between approval and execution.
- Apply runs each change as a job with retries. A failed change doesn't block the others; the plan shows what's left.
- The server runs refresh and plan on a schedule (every 15 minutes by default) and auto-applies only the change classes `lifecycle.yaml` allows. Everything else waits for approval in the UI.
- Drift (live differs from state) shows up in the next plan: remove it, or adopt it into YAML.
- A global dry run makes apply behave like plan. New installs start in dry run.

See [ADR 0005](adr/0005-configuration-as-code.md).

## Where the UI fits

The UI is a client of the same engine the CLI uses. It never writes to an application directly.

- **People**: browse identities, with a section per provider rendered from that provider's schema.
- **Plans**: review, approve, and apply. Shows the diff and the YAML change behind it.
- **Policies and modules**: read them rendered, see who each one matches, preview the impact of an edit.
- **Changes from the UI** (a manual grant, a new policy) are written as YAML and committed to the config repo, either directly or as a pull request depending on settings. Git history stays the audit trail of intent; the database keeps the audit trail of execution.
- **Providers**: what's installed, versions, the lock file, available upgrades from the registry.

## Platform

- PowerShell 7.4+ on [Pode](https://github.com/Badgerati/Pode) for the server, API, and scheduler ([ADR 0001](adr/0001-powershell-and-pode.md)). The same engine ships as a PowerShell module with an `iamasc` CLI for pipelines.
- Server-rendered pages with htmx. No JavaScript build step.
- JSON API under `/api/v1` for everything the UI does.
- State and audit backend behind a provider interface: SQLite first, SQL Server later ([ADR 0003](adr/0003-data-provider.md)).
- Sign-in with Entra ID, domain credentials against AD, or both, with roles from groups ([ADR 0004](adr/0004-authentication.md)).
- Secrets from `Microsoft.PowerShell.SecretManagement`. YAML references a secret by name, never contains one.
- Each provider's service account gets the least privilege the provider documents (AD: delegated rights on managed OUs only).

## Build order

Each step is its own feature branch and PR.

1. **Config engine**: load and validate YAML against JSON Schema, `iamasc validate`.
2. **State backend**: SQLite store, serials, locking, migrations.
3. **Provider protocol** and a mock provider with every permission shape, with contract tests.
4. **Plan**: compute desired state from a static HR file, diff against state and mock live, print the plan.
5. **Apply** with jobs, retries, saved plans, and audit.
6. **Active Directory provider**: accounts and groups, `import` for existing users.
7. **HR data sources**: CSV, then ADP.
8. **Server**: Pode app shell, sign-in, people pages, plan review and approval.
9. **Registry**: `init`, lock file, hash and signature checks, private registry support.
10. **Second provider** (Entra ID or Salesforce) to prove the model holds for a different permission shape.

## Open questions

- Should UI-made changes commit directly to the config repo, or always open a pull request?
- Which change classes auto-apply? Proposed: joiners, movers, and leavers from HR auto-apply; exceptions and anything marked privileged need approval.
- Username format and collision rule (first initial + last name assumed).
- Retention before deletion (90 days assumed) and who can set legal hold.
- Registry hosting: a public git index under this project, PSGallery with a naming prefix, or both.
- License for the public repository.

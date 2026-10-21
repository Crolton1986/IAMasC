# IAMasC concept

IAMasC is identity and access management as code. Every person has a YAML file in git that says who they are and what access they should have. IAMasC compares that with what each application really has, shows you a plan, and applies it. It works the way Terraform does for infrastructure: configuration, providers, modules, a registry, state, `plan`, and `apply`. A web UI sits on top for HR, managers, IT, and auditors who'll never open a YAML file.

This document is the long-term shape. Each feature that ships should fit it; when one doesn't, change this document in the same PR.

Clickable mockups: [docs/mockups/index.html](mockups/index.html) (open it in a browser). Example configuration: [examples/corp-chicago](../examples/corp-chicago) and [examples/server](../examples/server).

## The Terraform mapping

| Terraform | IAMasC | Example |
| --- | --- | --- |
| `.tf` files | YAML configuration in a git repo | `people/E-004611.yaml`, `policies/finance.yaml` |
| Provider | Plugin for one application, declaring its account and permission types | `iamasc/activedirectory`, `iamasc/salesforce` |
| Resource | An account or a permission grant in an application | an AD group membership |
| Data source | Read-only input, mainly HR | `iamasc/adp` workers |
| Module | Reusable, versioned bundle of grants with inputs. A role is a module. | `corp/finance-analyst` |
| Registry | Index of published providers, modules, and notifiers | the public git index or a private one |
| `.terraform.lock.hcl` | `.iamasc.lock.yaml` with versions and SHA-256 hashes | |
| Workspace | One config repo for one site or line of business | `corp-chicago`, `corp-warehouse` |
| State | What IAMasC created or adopted, with external IDs | `E-004127 / activedirectory.account → objectGUID` |
| `plan` / `apply` | Diff desired vs. state vs. live, then execute | `iamasc plan`, `iamasc apply` |
| `import` | Adopt accounts and grants that already exist | existing AD users on day one |
| Drift | Live differs from state | a group added by hand in ADUC |

## Where truth lives

| What | Source of truth | Written by |
| --- | --- | --- |
| Who exists, their job, manager, and dates | HR (ADP, CSV, or the manual hire form) | HR |
| A person's record and assigned roles | `people/<employee-id>.yaml` in the workspace repo | IAMasC from HR events; IAMasC after an approval |
| Baseline access everyone in a group gets | `policies/*.yaml` | IT, by pull request |
| What a role grants | `modules/*` or a shared module repo | IT, by pull request |
| Who must approve what | `approvals.yaml` | IT and security, by pull request |
| What IAMasC manages in each application | State in the database backend | IAMasC on apply |
| What the application has right now | The application itself | read on refresh |

Git holds only **approved** desired state. A request waiting for approval lives in IAMasC until it's approved; then IAMasC commits it with the approver's name and time. That keeps `main` meaning "what should be true", and git history becomes the complete record of every person: when they were hired, every role they were given, who approved it, and when it ended.

## The person file

When HR records a hire, IAMasC creates the person's file and commits it straight to the workspace repo. HR updates (a new title, a future termination date) rewrite the `hr` block in a new commit. People never edit the `hr` block by hand; IAMasC owns it and overwrites it from HR.

```yaml
# people/E-004611.yaml
apiVersion: iamasc.dev/v1
kind: Person
metadata:
  name: E-004611
spec:
  hr:                                   # owned by IAMasC, refreshed from HR
    source: adp
    syncedAt: 2026-10-21T09:00:00Z
    firstName: Grace
    lastName: Lindqvist
    department: Human Resources
    title: HR Generalist
    manager: E-001288
    location: Chicago
    workerType: Employee
    startDate: 2026-11-02
    terminationDate: null
  roles:                                # approved role assignments
    - module: corp/hris-admin
      version: "~> 1.0"
      from: 2026-11-02
      requestedBy: E-001288
      approvals:
        - { step: manager, by: E-001288, at: 2026-10-21T10:12:00Z }
        - { step: owner, by: E-000731, at: 2026-10-21T11:40:00Z }
  exceptions: []                        # one-off grants with ticket and expiry
```

Baseline access isn't listed in the file. It comes from policies that match HR attributes, so changing a policy updates everyone it matches without touching hundreds of files. The UI and `iamasc show E-004611` display the computed result: baseline plus roles plus exceptions.

## Approvals

Baseline access from policies applies without approval. Everything else goes through an approval chain, and each business defines its own chains in `approvals.yaml`. IAMasC ships no fixed approval logic. See [ADR 0008](adr/0008-approvals-and-notifications.md).

```yaml
apiVersion: iamasc.dev/v1
kind: ApprovalPolicy
metadata:
  name: default
spec:
  chains:
    standard:
      steps:
        - { approver: manager }
    application:
      steps:
        - { approver: manager }
        - { approver: owner }              # owner declared on the module or provider
    privileged:
      steps:
        - { approver: manager }
        - { approver: owner }
        - { approver: { group: IAMasC-Security }, minimum: 1 }
  rules:
    - match: { privileged: true }
      chain: privileged
    - match: { kind: Role }
      chain: application
    - match: { kind: Exception }
      chain: application
  timeouts:
    remindAfter: 2d
    escalateAfter: 5d                    # to the approver's manager
    expireAfter: 14d
```

Approver types: `manager` (from HR, walking up the chain if the manager has left), `owner` (named on the module or provider), a group, or a named person. A step can require one or several approvals. Approvals happen in the IAMasC UI, reached from a notification, so managers and application owners don't need GitHub accounts. The approver can't be the requester.

Joiners, movers, and leavers driven by HR apply automatically. A new hire gets baseline access on schedule, and any roles requested for them follow their own approval chain and apply when approved, even if that's after the start date.

## Dates and future changes

Every change can carry an effective date. A termination entered on October 2 for October 23 at 17:00 is written to the person file immediately, shows in the plan as scheduled, and applies at that time. Roles can have `from` and `until`. Exceptions must have an expiry. The scheduler runs plan continuously, so a change whose time has come appears and auto-applies if its class allows it.

## Workspaces: one repo per site or line of business

A company runs one IAMasC server with several workspaces. Each workspace is its own git repo with its own people, policies, approval chains, provider settings, and state. A shared repo holds company-wide modules any workspace can use. See [ADR 0007](adr/0007-workspaces.md).

```yaml
# server settings (iamasc-server.yaml), not in any workspace repo
apiVersion: iamasc.dev/v1
kind: Server
spec:
  workspaces:
    - name: corp-chicago
      repo: https://github.com/corp/iam-chicago.git
      branch: main
      match: { companyCode: "100" }
    - name: corp-warehouse
      repo: https://github.com/corp/iam-warehouse.git
      branch: main
      match: { companyCode: "200" }
  sharedModules:
    - namespace: corp
      repo: https://github.com/corp/iam-modules.git
  unmatched: hold                       # people matching no workspace wait in a queue
```

- Each HR worker belongs to exactly one workspace, chosen by HR fields (company code, business unit, location). A worker matching none waits in a queue for an admin.
- A transfer between workspaces moves the person file from one repo to the other in two linked commits, and plans both sides together so access isn't lost in between.
- Two workspaces can share one application (one AD domain) as long as each manages its own scope: different OUs, group prefixes, or subsidiaries. `iamasc validate` refuses overlapping scopes across workspaces.
- Sign-in roles are per workspace, so the warehouse IT team can't approve or change Chicago access.

## Configuration files in a workspace

| File | Kind | Purpose |
| --- | --- | --- |
| `iamasc.yaml` | Workspace | Required providers, HR source, naming rules, retention, settings |
| `lifecycle.yaml` | Lifecycle | What each HR status means for every account, and what auto-applies |
| `approvals.yaml` | ApprovalPolicy | Approval chains and which changes use which chain |
| `notifications.yaml` | Notifications | Where requests, approvals, failures, and drift are announced |
| `policies/*.yaml` | Policy | Baseline access matched on HR attributes |
| `modules/*/module.yaml` | Module | Roles: reusable bundles of grants across applications |
| `people/*.yaml` | Person | One per person: HR snapshot, approved roles, exceptions |
| `.iamasc.lock.yaml` | Lock | Exact provider and module versions with hashes |

Every document has `apiVersion` and `kind` so formats can evolve, and `iamasc validate` checks each one against JSON Schema, including the schemas providers publish. Full examples: [examples/corp-chicago](../examples/corp-chicago).

Everything a business might want to decide differently is a setting, not code: username and UPN templates and collision handling, OU placement, retention, approval chains, notification channels, auto-apply classes, pre-provisioning days.

```yaml
# from iamasc.yaml
naming:
  activedirectory:
    username: "{{ first | initial | lower }}{{ last | lower | ascii }}"
    collision: append-number            # or: fail, use-middle-initial
    upn: "{{ preferredFirst | default: first | lower }}.{{ last | lower }}@corp.example.com"
retention:
  default: never                        # accounts stay disabled unless a workspace opts in
  overrides:
    salesforce: 30d                     # free the license sooner
```

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
      license:  { type: enum, source: catalog, countable: true }
  permissions:
    profile:
      shape: single
      source: catalog
    permissionSet:
      shape: set
      source: catalog
      privileged: [Modify_All_Data, Author_Apex]
```

| Shape | Meaning | Example | UI |
| --- | --- | --- | --- |
| `single` | Exactly one value | Salesforce profile, M365 license plan | A labeled value |
| `set` | Any number of values from a catalog | AD groups, Salesforce permission sets | A list with origin and dates |
| `scoped` | A value at a scope | Azure role at subscription, NetSuite role at subsidiary | A table of scope and role |
| `matrix` | Privileges on objects | SQL `SELECT` on `finance.ledger` | An object × privilege grid |
| `attribute` | A plain account property | AD `title`, `manager` | Shown under the account |

A provider implements a fixed set of functions over that schema: `Get-Schema`, `Get-Catalog`, `Read-Account`, `Read-Permissions`, `Plan-Change`, `Invoke-Change`, `Import-Account`. Providers can mark permissions as privileged, which feeds the approval rules. See [ADR 0002](adr/0002-provider-contract.md).

## Notifications

Notification channels are plugins too, published in the registry like providers. Email, Microsoft Teams, Slack, and a generic webhook ship with IAMasC; a business can add others (ServiceNow, Jira, PagerDuty) without changing the core.

```yaml
apiVersion: iamasc.dev/v1
kind: Notifications
spec:
  channels:
    email:        { notifier: iamasc/email, config: { via: graph, from: iam@corp.example.com } }
    teams-direct: { notifier: iamasc/teams, config: { mode: chat } }          # message the person
    teams-it:     { notifier: iamasc/teams, config: { mode: channel, webhook: { secret: teams-it-webhook } } }
    slack-it:     { notifier: iamasc/slack, config: { channel: "#iam-alerts", token: { secret: slack-bot } } }
    servicenow:   { notifier: iamasc/webhook, config: { url: https://corp.service-now.com/api/iam, auth: { secret: snow-token } } }
  routes:
    - event: approval.requested
      to: [approver]
      via: [email, teams-direct]
    - event: [apply.failed, drift.found]
      via: [teams-it, slack-it, servicenow]
    - event: leaver.scheduled
      to: [manager]
      via: [email]
```

## Registry

Providers, modules, and notifiers are versioned packages listed in a registry. The public registry is a git repository with a signed index file maintained by this project. A company can run a private one (any git repo or file share with the same index format) for internal modules.

- `iamasc init` resolves version constraints, downloads packages, verifies their SHA-256 hashes and signatures, and writes `.iamasc.lock.yaml`.
- Upgrades only happen through a pull request that changes the lock file, so they pass the same review and security gates as code.
- Providers declare the protocol version they speak, so the core can refuse an incompatible one.
- PowerShell modules are the package format underneath, so anyone who knows PowerShell can write a provider.

See [ADR 0006](adr/0006-registry.md).

## Plan and apply

```text
$ iamasc plan -workspace corp-chicago
Refreshing state... 203 people, 3 providers

  # E-004611 Grace Lindqvist · joiner · applies 2026-10-30 06:00
  + activedirectory.account  glindqvist  (disabled until 2026-11-02 07:00)
  + activedirectory.group    GG-AllStaff, GG-Chicago, GG-HR-All
  + workday.role             HRIS Admin            (role corp/hris-admin, approved)

  # E-004127 Maria Okafor · mover Finance -> Treasury · applies 2026-11-02 06:00
  - activedirectory.group    GG-SharePoint-Finance
  + activedirectory.group    GG-Treasury-All
  ~ salesforce.profile       Finance User -> Treasury User

  # E-003318 Dan Whitfield · leaver · applies 2026-10-23 17:00
  ~ activedirectory.account  dwhitfield  enabled -> disabled, move to OU=Disabled Users
  - activedirectory.group    6 groups (snapshot saved)
  ~ salesforce.account       active -> frozen, license released

Plan: 7 to add, 3 to change, 7 to remove. Config 8f3c21a.
```

- A plan is saved and applied exactly as shown, never recomputed between approval and execution.
- Apply runs each change as a job with retries. A failed change doesn't block the others; the plan shows what's left.
- The server runs refresh and plan on a schedule (every 15 minutes by default) and applies what's due.
- Drift (live differs from state) shows up in the next plan: remove it, or adopt it into the person's file through an approval.
- A global dry run makes apply behave like plan. New installs start in dry run.

See [ADR 0005](adr/0005-configuration-as-code.md).

## Where the UI fits

The UI is a client of the same engine the CLI uses. It never writes to an application directly.

- **People**: one page per person, with a section per provider rendered from that provider's schema, the person file, and its git history.
- **Requests and approvals**: request a role for someone, approve or deny what's waiting on you.
- **Plans**: what's scheduled, what's waiting, what failed.
- **Policies, modules, and approval chains**: rendered views of the YAML, who each one matches, impact previews. Edits open a pull request.
- **Providers and workspaces**: installed versions, the lock file, registry upgrades, which repo each site uses.

## Platform

- PowerShell 7.4+ on [Pode](https://github.com/Badgerati/Pode) for the server, API, and scheduler ([ADR 0001](adr/0001-powershell-and-pode.md)). The same engine ships as a PowerShell module with an `iamasc` CLI for pipelines.
- Server-rendered pages with htmx. No JavaScript build step.
- JSON API under `/api/v1` for everything the UI does.
- State and audit backend: SQLite first, SQL Server later ([ADR 0003](adr/0003-data-provider.md)).
- Sign-in with Entra ID, domain credentials against AD, or both, with roles per workspace from groups ([ADR 0004](adr/0004-authentication.md)).
- Git access through a GitHub App or deploy key per workspace repo. IAMasC signs its commits.
- Secrets from `Microsoft.PowerShell.SecretManagement`. YAML references a secret by name, never contains one.
- Each provider's service account gets the least privilege the provider documents.

## Build order

Each step is its own feature branch and PR.

1. **Config engine**: load and validate YAML against JSON Schema, `iamasc validate`.
2. **State backend**: SQLite store, serials, locking, migrations.
3. **Provider protocol** and a mock provider with every permission shape, with contract tests.
4. **Plan**: compute desired state from person files and policies, diff against state and mock live, print the plan.
5. **Apply** with jobs, retries, saved plans, scheduling, and audit.
6. **Git writer**: create and update person files from HR events, signed commits, one workspace repo.
7. **Active Directory provider**: accounts and groups, configurable naming, `import` for existing users.
8. **HR data sources**: manual form and CSV, then ADP.
9. **Server**: Pode app shell, sign-in, people pages, plans.
10. **Approvals and notifications**: approval chains, requests, email, Teams, Slack, webhook.
11. **Multiple workspaces** and shared module repos.
12. **Registry**: `init`, lock file, hash and signature checks, private registry support.
13. **Second provider** (Entra ID or Salesforce) to prove the model holds for a different permission shape.

## Decisions made

| Question | Decision |
| --- | --- |
| How YAML reaches git | HR-driven person files commit directly. Policy, module, and approval changes go through pull requests. Approved requests commit directly with the approval recorded. |
| What auto-applies | Joiners, movers, and leavers from HR. Roles and exceptions apply once their approval chain completes. Policy changes apply after their pull request merges. |
| Approvals | Chains are configured per workspace. Approvers can be the manager, the module or provider owner, a group, or a person. Approvals happen in the IAMasC UI. |
| Repos | One repo per site or line of business, matched on HR fields, plus shared module repos. |
| Person file | HR snapshot, approved roles, and exceptions. |
| Usernames | A template per workspace and provider, with a configurable collision rule. |
| Retention | Configurable per workspace and provider. Default: never delete. Legal hold blocks deletion. |
| Notifications | Plugins. Email, Teams, Slack, and webhook ship by default. |
| Registry | Git index repository with signed packages; private registries use the same format. |
| License | Apache-2.0. |

## Open questions

- Self-service requests: should employees request roles for themselves, or only managers and IT?
- Access reviews: periodic re-certification of roles and exceptions by managers (a natural next feature on top of approvals).

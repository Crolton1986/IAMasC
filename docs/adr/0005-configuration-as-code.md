# 0005: Access as code with plan and apply

- Status: Accepted
- Date: 2026-10-21

## Context

Access rules buried in a database are hard to review, hard to audit, and hard to move between environments. Terraform showed that declaring desired state in files, reviewing a computed plan, and applying it gives teams review, history, and repeatability. Identity access has the same needs, plus one difference: the list of people changes daily and comes from HR.

## Decision

- Desired access is declared in YAML documents (`Workspace`, `Person`, `Policy`, `Module`, `Lifecycle`, `ApprovalPolicy`, `Notifications`), each with `apiVersion` and `kind`, stored in a git repository and validated against JSON Schema.
- Every person has a file, `people/<employee-id>.yaml`, created by IAMasC when HR records a hire. It holds an HR snapshot that IAMasC overwrites from HR, plus approved roles and exceptions. HR-driven updates commit directly so onboarding never waits on review.
- Baseline access comes from policies matched on HR attributes and isn't copied into person files. Desired state per person is computed from the HR snapshot, policies, roles, and exceptions.
- Git holds only approved desired state. Requests wait in IAMasC until their approval chain completes, then commit with the approvals recorded.
- IAMasC keeps state: every account and permission it manages, keyed by an address like `E-004127/activedirectory/group/GG-Finance-All`, with the external ID and last-known attributes. State has a serial and a lock.
- `plan` refreshes live state, diffs desired against it, and saves the result. `apply` executes a saved plan exactly as shown.
- The server runs plan on a schedule and auto-applies only change classes the `Lifecycle` document allows. The rest wait for approval.
- Policy, module, and approval-chain changes from the UI open pull requests; approved access requests and HR updates commit directly. Both are configurable per workspace.

## Consequences

- Joiner, mover, and leaver become attribute changes that produce plans, not separate code paths. Future-dated changes sit in the person file and apply when due.
- The git history of `people/` is a full record of each person: hire, every role, who approved it, and when it ended.
- Access changes get code review, history, and rollback through git.
- Brownfield adoption needs `import`, so existing accounts and groups can enter state without being recreated.
- Two audit trails exist and must link: git for intent, the database for execution. Each apply records the config commit it ran from.
- YAML is less expressive than HCL. Templating is limited to `{{ person.<attribute> }}` substitutions on purpose; logic belongs in policies' `match` and in modules.

## Alternatives considered

- Rules stored in the database and edited only in the UI (the earlier concept): simpler to start, but no review workflow, no history, and no way to manage access like code.
- No person files, with people only in HR: fewer commits, but the repo alone couldn't answer "what did this person have, and who approved it".
- Copying baseline grants into every person file: explicit, but a one-line policy change would rewrite hundreds of files and bury real changes in noise.
- A Terraform provider for identity: reuses Terraform, but Terraform has no notion of a daily HR feed, approval classes, or a UI for HR staff.
- HCL instead of YAML: more expressive, but the audience is admins and HR tooling, where YAML is familiar and parsers exist everywhere.

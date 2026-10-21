# 0005: Access as code with plan and apply

- Status: Accepted
- Date: 2026-10-21

## Context

Access rules buried in a database are hard to review, hard to audit, and hard to move between environments. Terraform showed that declaring desired state in files, reviewing a computed plan, and applying it gives teams review, history, and repeatability. Identity access has the same needs, plus one difference: the list of people changes daily and comes from HR.

## Decision

- Desired access is declared in YAML documents (`Workspace`, `Policy`, `Module`, `Grant`, `Lifecycle`), each with `apiVersion` and `kind`, stored in a git repository and validated against JSON Schema.
- The list of people and their attributes comes from HR data sources, not YAML. Desired state per person is computed from HR attributes, policies, modules, and explicit grants.
- IAMasC keeps state: every account and permission it manages, keyed by an address like `E-004127/activedirectory/group/GG-Finance-All`, with the external ID and last-known attributes. State has a serial and a lock.
- `plan` refreshes live state, diffs desired against it, and saves the result. `apply` executes a saved plan exactly as shown.
- The server runs plan on a schedule and auto-applies only change classes the `Lifecycle` document allows. The rest wait for approval.
- The UI writes changes as YAML commits (directly or as a pull request), so it never bypasses review.

## Consequences

- Joiner, mover, and leaver become attribute changes that produce plans, not separate code paths.
- Access changes get code review, history, and rollback through git.
- Brownfield adoption needs `import`, so existing accounts and groups can enter state without being recreated.
- Two audit trails exist and must link: git for intent, the database for execution. Each apply records the config commit it ran from.
- YAML is less expressive than HCL. Templating is limited to `{{ person.<attribute> }}` substitutions on purpose; logic belongs in policies' `match` and in modules.

## Alternatives considered

- Rules stored in the database and edited only in the UI (the earlier concept): simpler to start, but no review workflow, no history, and no way to manage access like code.
- A Terraform provider for identity: reuses Terraform, but Terraform has no notion of a daily HR feed, approval classes, or a UI for HR staff.
- HCL instead of YAML: more expressive, but the audience is admins and HR tooling, where YAML is familiar and parsers exist everywhere.

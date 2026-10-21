# 0007: One workspace repo per site or line of business

- Status: Accepted
- Date: 2026-10-21

## Context

Larger companies run several sites or lines of business with their own IT teams, approvers, and sometimes their own applications. One shared repo would give every team write access to everyone's people and policies, and one shared state would let a mistake in one site's config touch another's accounts.

## Decision

- A **workspace** is one git repo with its own people, policies, modules, approval chains, provider settings, and state.
- The IAMasC server lists workspaces in its server settings. Each has a repo, a branch, and an HR match (company code, business unit, location). Every HR worker belongs to exactly one workspace; workers matching none wait in a queue for an admin.
- **Shared module repos** hold company-wide roles under a namespace (for example `corp/`) that any workspace can use, versioned like registry modules.
- Workspaces sharing an application declare a **scope** (OUs, group prefixes, subsidiaries). `iamasc validate` refuses overlapping scopes, and providers refuse writes outside their workspace's scope.
- A transfer between workspaces moves the person file in two linked commits, and the plan covers both sides at once so access isn't dropped in between.
- Sign-in roles are granted per workspace.

## Consequences

- Each site owns its repo, reviewers, and approval rules. Repository permissions in GitHub match organizational boundaries.
- A single-site company runs one workspace, so the model costs nothing until it's needed.
- Cross-workspace reporting (all access for all people) is done by the server over all states, not by reading one repo.
- Scope declarations become mandatory once two workspaces share an application.

## Alternatives considered

- One repo with a folder per site and CODEOWNERS: simpler, but every team can read everything, and one bad merge can affect all sites.
- One server per site: full isolation, but no shared modules, transfers become manual, and there's no company-wide view.

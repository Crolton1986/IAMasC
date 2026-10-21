# 0008: Configurable approval chains and notifier plugins

- Status: Accepted
- Date: 2026-10-21

## Context

Who must approve access differs between companies and between teams in one company. Some want only the manager, some want the application owner, some want security for anything privileged. Managers and application owners usually don't have GitHub accounts. Companies also announce things through different tools: Teams, Slack, email, ServiceNow.

## Decision

- Baseline access from policies needs no approval. HR-driven joiners, movers, and leavers apply automatically.
- Roles and exceptions go through an **approval chain** defined in `approvals.yaml`: ordered steps, each naming an approver type (`manager`, `owner`, a group, or a person) and how many approvals it needs. Rules choose a chain by request kind and by whether a permission is privileged. Timeouts remind, escalate, and expire requests.
- Owners are declared on modules or providers. Providers mark permissions as privileged in their schema.
- Approvals happen in the IAMasC UI, reached from a notification. An approver can't approve their own request. When a chain completes, IAMasC commits the change to the person file with every approval recorded.
- Notifications are plugins (`kind: Notifier` packages in the registry). Email, Microsoft Teams, Slack, and a generic webhook ship with IAMasC. `notifications.yaml` maps events to channels and recipients.

## Consequences

- No approval logic is hard-coded, so each workspace matches its own process.
- Approvers need only an IAMasC sign-in, not a GitHub account.
- Approval records live in git (in the person file) and in the audit log, so both trails agree.
- Pending requests live in the database until approved, so `main` only ever shows approved access.
- New notification targets don't need a core release.

## Alternatives considered

- Pull-request review as the approval: strong trail, but every manager would need a GitHub account and to read YAML diffs.
- A fixed manager-then-owner chain: simpler, but wrong for many companies.
- Built-in Teams and Slack code instead of plugins: fewer moving parts, but every new target would need a core change.

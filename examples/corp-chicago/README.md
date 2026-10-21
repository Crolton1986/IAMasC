# Example workspace: corp-chicago

A sample IAMasC workspace for a fictional company's Chicago site (HR company code 100). It shows the file formats and is used by tests once the config engine exists. Nothing in it points at real systems. A second site would be its own repo, listed in [../server/iamasc-server.yaml](../server/iamasc-server.yaml).

| File | Kind | What it declares |
| --- | --- | --- |
| `iamasc.yaml` | Workspace | Providers, HR source, scope, naming, retention, git settings |
| `lifecycle.yaml` | Lifecycle | What each HR status means for every account, and what auto-applies |
| `approvals.yaml` | ApprovalPolicy | Approval chains and which requests use them |
| `notifications.yaml` | Notifications | Channels (email, Teams, Slack, webhook) and what goes where |
| `policies/*.yaml` | Policy | Baseline access matched on HR attributes |
| `modules/*/module.yaml` | Module | Roles: reusable bundles of grants, with an owner who approves |
| `people/*.yaml` | Person | One per person: HR snapshot, approved roles, exceptions |
| `.iamasc.lock.yaml` | Lock | Exact provider and module versions with hashes, written by `iamasc init` |

The people files show three cases: a new hire with an approved role (`E-004611`), a mover with a privileged exception (`E-004127`), and a future-dated leaver (`E-003318`).

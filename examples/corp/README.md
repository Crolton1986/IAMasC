# Example workspace: corp

A sample IAMasC configuration for a fictional company. It's here to show the file format and is used by tests once the config engine exists. Nothing in it points at real systems.

| File | Kind | What it declares |
| --- | --- | --- |
| `iamasc.yaml` | Workspace | Required providers, HR source, state backend |
| `lifecycle.yaml` | Lifecycle | What each HR status means for every account, and what auto-applies |
| `policies/*.yaml` | Policy | Which people get which modules, matched on HR attributes |
| `modules/*/module.yaml` | Module | A reusable bundle of grants across applications |
| `identities/*.yaml` | Grant | Exceptions for one person, with a ticket, approver, and expiry |
| `.iamasc.lock.yaml` | Lock | Exact provider and module versions with hashes, written by `iamasc init` |

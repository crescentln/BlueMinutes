# Task 009A Automation Command Layer and CLI

Status: Accepted by the user on 2026-07-21
Date: 2026-07-21
Rollback Git anchor: `2a38a74aedf42d0e69f2375bd21365132e340cf4`
Implementation commit: `31661a352a5ecf64f8ef3bf8ae9069e6ab16a1d0`
Architecture decision: [ADR-0014](adr/ADR-0014-task-009a-automation-command-boundary.md)

## Implemented boundary

`MeetingBuddyApplication` defines the closed versioned contracts,
`MeetingBuddyAutomation` owns the sole command dispatcher and CLI parser,
`MeetingBuddyPersistence` owns the SQLite implementation, and
`meetingbuddy-cli` only composes those components for an already-existing local
workspace. Command input cannot supply a permission, role, confirmation,
recursion exemption, database handle, provider, model, or filesystem path.

## Typed command catalog

| Command | Permission | Policy scope | Business-state change | Restricted task directory |
| --- | --- | --- | --- | --- |
| `get_command_catalog` | `read` | workspace | no | no |
| `get_workspace_status` | `read` | workspace | no | no |
| `get_meeting_policy_status` | `read` | exact current meeting graph | no | no |
| `get_storage_report` | `read` | workspace | no | no |
| `get_settings` | `read` | workspace | no | no |
| `describe_settings` | `read` | workspace | no | no |
| `list_activity` | `read` | workspace | no | no |
| `update_settings` | `safe_configuration` | workspace | typed settings only | no |
| `rollback_settings` | `safe_configuration` | workspace | server-side inverse only | no |
| `run_workspace_diagnostics` | `operational` | workspace | no | yes |

The only patchable value is `status_list_limit`, an unsigned integer from 1
through 200 with compiled default 50. It controls the default bounded activity
list length. All protected settings are descriptive only and cannot be patched.

## Unavailable sensitive capabilities

Export, provider/model work, recording, job mutation, destructive filesystem
operations, credentials, access-policy mutation, arbitrary path/database
access, remote network control, MCP, and HTTP are rejected before dispatch.
Future export, recording, destructive filesystem, credential, access-policy,
and remote-control capabilities are catalogued as requiring trusted visible
one-time application confirmation. No Task 009A CLI confirmation flag exists.

## Authorization and policy matrix

| Condition | Result | Durable evidence |
| --- | --- | --- |
| Caller permission meets command permission | continue | actor, origin, granted/required permission |
| Permission is insufficient | reject | `permission_denied` result |
| Nested MeetingBuddy/provider call | reject | root/parent/hop metadata and denial |
| Replay nonce already claimed | reject | replay command linked to original command |
| Meeting graph is exact, active, current, published, and valid | read status | three exact input revisions and effective classification |
| Meeting policy is missing, stale, ambiguous, or invalid | reject | safe policy-denial code; no content |
| Workspace-only command | local/content-free route | policy version and `not_applicable` model disposition |

## CLI surface

```text
meetingbuddy-cli --workspace <absolute-path> [--command-id <uuid>] [--replay-nonce <uuid>] <command>

catalog
status workspace
status meeting-policy --meeting-id <uuid>
status storage [--maximum-entries <1...100000>]
settings get
settings describe
settings patch --expected-version <n> --status-list-limit <1...200>
settings rollback --target-command-id <uuid> --expected-version <n>
activity list [--limit <1...200>]
diagnostics run [--maximum-entries <1...100000>]
```

The executable accepts no relative, root, traversal, repeated-separator, or
symlinked workspace path. Output is canonical JSON with stable safe exit/error
classes. It prints no raw argv, workspace path, meeting content, secret, or raw
framework/database error.

## Persistence and recovery

Schema v8 adds:

- `automation_command_records` and one claimed-nonce unique index;
- `automation_command_input_revisions` for exact policy inputs;
- `automation_command_result_events` with one immutable terminal event per
  command;
- `automation_settings_state` as the singleton compare-and-swap projection;
- `automation_settings_events` as the immutable patch/rollback chain.

All audit/event payloads are bounded canonical JSON with SHA-256 and indexed
field checks. Immutable tables reject update/delete. Settings projection,
event, and successful result commit atomically. Recovery verification decodes,
canonicalizes, hashes, and cross-checks the full automation event/settings
chain. The v7-to-v8 migration preserves exact pre-existing semantic bytes,
creates a readable source-version-7 rollback backup, and writes no default
settings row.

## Validation evidence

Focused tests cover the closed catalog, CLI/application parity, invalid typed
input, unavailable export/recording/provider/destructive/MCP/HTTP requests,
unforgeable authority, permission levels, recursion, exact current policy,
missing policy denial, replay claims, attribution, immutable audit rows,
settings compare-and-swap, inverse rollback, injected transactional failure,
restricted-directory cleanup, path confinement, recovery, and fresh/v1-v7
migration compatibility.

The final command/results and complete-suite count are recorded in
`docs/CODEX_EXECUTION_STATE.md`. Tests use synthetic data and disposable local
workspaces only. No user workspace, real meeting content, provider, network,
credential, export, recording, MCP, or remote system is used.

## Residual limits

- The SwiftUI app has no new automation UI; Task 009A proves the shared layer
  and CLI transport only.
- No sensitive/destructive command is implemented, so confirmation is proven
  by absence plus fail-closed catalog/parser tests rather than live execution.
- Xcode GUI/manual release, assistive-technology, and signed/notarized CLI
  checks remain unverified release work.
- Task 009B and every other later task remain unauthorized until the user
  separately authorizes the next task.

The Task 009A implementation and completion evidence were committed locally as
`31661a352a5ecf64f8ef3bf8ae9069e6ab16a1d0` and accepted by the user on
2026-07-21. No branch, tag, push, release, deployment, or next-task work was
performed.

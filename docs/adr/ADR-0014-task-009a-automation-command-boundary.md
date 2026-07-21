# ADR-0014: Task 009A Automation Command and CLI Boundary

Status: Accepted for implementation
Date: 2026-07-21
Decision owners: User and Codex
Applies from: Task 009A

## Context

MeetingBuddy needs a local automation surface before any MCP, enterprise, or
remote adapter can be considered. Direct transport access to SQLite, workspace
paths, providers, exports, recording, credentials, or policy mutation would
bypass the application-owned privacy and authorization model. Existing export
and recording confirmations are purpose-specific UI contracts and are not
transferable Boolean flags that a CLI may forge.

ADR-0001 originally named `MeetingBuddyApp` as the sole composition root. Task
009A needs a second local executable transport while preserving the same
application command boundary and keeping concrete persistence out of command
payloads.

## Decision

### D1. One shared typed command layer

`MeetingBuddyApplication` owns versioned command, caller, permission, policy,
result, audit, settings, and repository contracts. `MeetingBuddyAutomation`
owns the sole dispatcher and strict CLI adapter. The SwiftUI app remains the UI
composition root; `meetingbuddy-cli` is a second thin local transport
composition root over the same dispatcher. This narrowly refines ADR-0001 and
does not expose persistence to features, commands, or callers.

### D2. Closed Task 009A command catalog

The accepted catalog contains only:

- catalog, workspace, current meeting-policy, and aggregate storage status;
- current settings, settings description, and bounded activity status;
- a compare-and-swap patch and server-side inverse rollback for
  `status_list_limit` in the closed range `1...200`;
- bounded workspace diagnostics using one restricted `.tasks/<UUID>` directory.

Export, provider/model selection or execution, recording, job mutation,
destructive filesystem operations, credentials, access-policy mutation,
arbitrary paths or database access, remote network control, MCP, and HTTP are
unavailable capabilities. No generic command escape hatch exists.

### D3. Authority is composition-owned

Callers receive `read`, `safe_configuration`, `operational`, or `sensitive`
maximum authority only from a trusted composition root. Role, permission,
confirmation, and recursion flags are not command input. The CLI is fixed at
`operational`, which cannot unlock an unavailable sensitive command.

Every request carries a command ID and one replay nonce. A unique durable claim
precedes execution. Reused nonces are rejected and attributed to the original
command. A nested MeetingBuddy hop or inference-provider ancestor is denied by
default.

### D4. Policy and confirmation fail closed

Meeting-scoped status requires the exact active, current, published
`MeetingProfile.v1`, `SensitivityLabel.v1`, and `AccessPolicy.v1` graph and runs
`SecurityPolicyGraphValidator`. Audit records bind those exact revisions and
the effective classification. Workspace commands are content-free local
operations, cannot alter policy or provider/model routing, and record the
model-route disposition as `not_applicable`.

No sensitive or destructive command is exposed in Task 009A. The catalog
records that any future export, recording, destructive filesystem, credential,
access-policy, or remote-control capability requires a trusted-application
one-time confirmation. A CLI `--confirm` value is rejected and cannot stand in
for visible application authorization.

### D5. SQLite v8 is the audit/settings authority

Migration `008_automation_command_audit_settings` adds immutable command
records, exact normalized policy-input revisions, immutable result events, a
single versioned settings projection, and immutable settings events. Command
and result payloads contain only canonical bounded metadata, opaque IDs,
digests, safe codes, permission/policy decisions, and rollback references. They
exclude meeting content, filenames, arbitrary paths, raw argv, credentials,
provider output, and raw errors.

The compiled settings default is version zero and is not fabricated during
migration. The first patch creates version one. Each later patch or rollback
advances exactly one version, checks the expected current version, and commits
the settings event, projection, and successful result in one transaction.

### D6. CLI paths and output are bounded

The executable requires one explicit canonical absolute workspace path and
rejects root, relative, traversal, repeated-separator, control-character, and
symlinked paths before opening the existing workspace. It has no create,
delete, SQL, arbitrary file, network, provider, recording, export, credential,
or access-policy command.

Success and failure output is deterministic bounded JSON. Failures use stable
codes and process exit classes without printing raw errors, paths, content, or
secrets.

## Consequences

- Read commands mutate only mandatory schema/audit metadata, never semantic,
  job, settings, managed-file, provider, recording, or export business state.
- A future adapter must use this shared layer and requires its own authorized
  task and threat review; Task 009A adds no MCP or local HTTP surface.
- Sensitive operations remain absent instead of reusing forgeable Boolean
  confirmation fields.
- The CLI can be removed without changing semantic data. Durable v8 audit data
  remains readable by the accepted application version.

## Rollback

Disable or remove the CLI product to roll back the transport without touching
workspace data. Revert application code to the pre-Task-009A Git anchor for a
source rollback. A schema downgrade must restore the verified automatic v7
pre-migration SQLite backup; do not delete v8 tables in place.

## Explicitly deferred

MCP, HTTP, arbitrary database/filesystem commands, remote control,
subscription-provider work, organization synchronization, enterprise
administration, cross-organization access management, and real-time coaching
remain outside Task 009A and require separate authorization.

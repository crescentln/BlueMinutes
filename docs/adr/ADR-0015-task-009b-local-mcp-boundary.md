# ADR-0015: Task 009B Local Read-Only MCP Boundary

Status: Accepted
Date: 2026-07-21
Decision owners: User and Codex
Applies from: Task 009B

## Context

Task 009A established one typed application command boundary and a local CLI.
Task 009B authorizes an MCP adapter, but does not by itself approve a network
listener, an organization or cloud destination, an account-backed provider, a
credential flow, or transfer of meeting data. MeetingBuddy already retains
accepted local Apple on-device provider routes and manual local review
fallbacks, so MCP does not need a new inference provider to remain optional.

MCP clients are external callers. Their declared identity, capabilities, tool
arguments, and metadata are untrusted input and cannot grant authority or
stand in for visible user approval.

## Decision

### D1. Local stdio is the only MCP transport

`meetingbuddy-mcp` implements the stable MCP protocol version `2025-11-25`
over newline-delimited UTF-8 JSON-RPC on standard input/output. Standard output
contains protocol messages only. Help and bounded safe failures use standard
error. There is no HTTP, Streamable HTTP, socket, listener, discovery,
advertisement, or remote-control surface.

The server is launched only with this exact shape:

```text
meetingbuddy-mcp --workspace <absolute-path> --approve-read-tools-with-local-audit
```

The explicit approval flag and configuration of that local command are the
connection approval. They approve bounded local audit writes and, when opening
an accepted schema-v8 workspace, creation of its verified rollback backup and
migration of the audit-origin vocabulary to schema v9. The workspace must
already exist and pass the accepted canonical absolute, non-root, non-
traversing, non-symlink path checks.

### D2. The MCP surface is a fixed seven-tool allowlist

The adapter exposes only:

- `describe_settings`;
- `get_command_catalog`;
- `get_meeting_policy_status`;
- `get_settings`;
- `get_storage_report`;
- `get_workspace_status`;
- `list_activity`.

Each tool maps to the existing `AutomationCommandExecuting` port. The allowlist
is explicit and independent of future catalog additions. `update_settings`,
`rollback_settings`, `run_workspace_diagnostics`, and every unavailable
capability remain absent. No generic command, SQL, path, file, provider, model,
export, recording, credential, policy-mutation, or process argument exists.

Read commands still append bounded local audit metadata. The tools therefore
do not claim MCP read-only or idempotent annotations even though they cannot
change MeetingBuddy business state.

### D3. Authority remains composition-owned

The executable constructs a fixed caller with origin `mcp`, actor `local_mcp`,
maximum permission `read`, adapter version `meetingbuddy-mcp-stdio-v1`, and an
external-agent boundary. Client name/version and `_meta` are never used for
authorization. Request input cannot provide command IDs, replay nonces,
permissions, roles, confirmation, recursion state, workspace authority, or
provider/model policy. The server generates command IDs and replay nonces.

Task 009A recursion denial remains authoritative for MeetingBuddy or inference-
provider ancestors. This executable is not launched by MeetingBuddy and offers
no client-controlled ancestry exemption.

### D4. Protocol input and failures are bounded

The server follows the MCP initialize/initialized lifecycle and advertises
only the tools capability. It supports `ping`, `tools/list`, and `tools/call`;
resources, prompts, sampling, elicitation, logging, completions, and MCP tasks
are not advertised or implemented.

Messages are limited to 1 MiB before JSON decoding. Methods, identifiers,
client identity fields, tool names, object keys, numeric bounds, and result
size are validated. Tool calls are serialized and limited to 120 per rolling
minute by default. Unknown tools and malformed parameters fail before the
application dispatcher. Application failures are mapped to stable safe codes;
raw framework, database, path, content, or credential errors are not returned.
Successful tools return the same typed `AutomationCommandExecution` both as
canonical JSON text and `structuredContent`.

### D5. SQLite v9 records truthful MCP attribution

The accepted v8 audit table allowed only `application` and `cli` origins.
Aliasing MCP as CLI would corrupt provenance, so ordered migration
`009_mcp_audit_origin` rebuilds only `automation_command_records` with `mcp` in
the closed origin check. It copies every indexed field and canonical payload
byte, recreates indexes and immutability triggers, updates schema metadata, and
does not create settings, semantic objects, or provider metadata.

Opening an accepted v8 workspace creates the existing verified online v8
rollback backup before migration. A schema downgrade restores that backup; it
does not delete or rewrite v9 audit rows in place.

### D6. No additional provider is approved or added

No organization-hosted, approved-cloud, Codex subscription, Claude Code
subscription, or other experimental provider has a separately approved
destination, retention, deployment, account, quota, credential, and data-
policy contract in this task. None is implemented. No credential is read,
stored, logged, copied, or requested, and no Keychain behavior changes.

The accepted Apple on-device ASR/translation/Foundation Models routes and
manual local review remain the supported local/offline fallback. MCP is a
command transport only and cannot select or invoke a provider/model route.

### D7. No MCP SDK dependency is added

The small tools-only stdio boundary is implemented with Foundation and the
existing typed command contracts. This avoids adding a pre-1.0 SDK and its
transitive dependencies for a surface that needs no client, HTTP transport,
resources, prompts, or sampling. The protocol implementation is covered by
fixture tests against the stable specification behavior.

## Consequences

- MCP can be removed by deleting one executable target and one adapter file;
  the application, CLI, local providers, and manual fallback remain usable.
- Removing MCP does not make semantic objects or settings unreadable. Schema
  v9 audit rows remain readable by code that knows the truthful `mcp` origin.
- Every MCP tool invocation is locally attributable and replay-protected, but
  no meeting/transcript content, filename, workspace path, or raw error is
  added to audit output.
- A future transport, write tool, or provider requires a separate explicit
  authorization and its own policy/data contract.

## Rollback

Disable or remove the `meetingbuddy-mcp` product and
`AutomationMCPAdapter.swift` to remove the transport. Retain schema v9 when
audit history must remain readable. For a full source/schema rollback, restore
the verified automatic pre-migration v8 backup and the pre-Task-009B Git
anchor; do not perform an in-place table downgrade.

## Protocol references

- [MCP 2025-11-25 lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle)
- [MCP 2025-11-25 transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
- [MCP 2025-11-25 tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)
- [MCP 2025-11-25 ping](https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/ping)

## Explicitly deferred

Streamable HTTP, remote MCP access, resources, prompts, sampling, tasks,
provider/model execution, local-model installation, organization/cloud
destinations, subscription-client automation, account/login flows, credential
handling, export, recording, arbitrary filesystem/database access, remote
control, and all Task 010 behavior remain outside this decision.

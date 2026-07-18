# Security and Privacy Baseline

Status: Task 005A local file-authority and full-Xcode native gates verified;
provider-route enforcement remains deferred
Owner: Codex
Last updated: 2026-07-18
Purpose: Define classification, routing, secret, logging, and trust-boundary
requirements. Provider details belong in ADRs and later implementation tasks.

## Data classification

Every source and derived semantic object must carry one classification:

| Class | Default processing rule |
| --- | --- |
| `public` | Cloud processing is permitted only when the user enables an allowed provider. |
| `internal` | Cloud processing requires explicit meeting or workspace policy. |
| `sensitive` | Local by default; external processing requires an explicit policy and clear disclosure. |
| `restricted` | No external processing unless a separately approved institutional policy permits it. |

Derived data inherits the highest classification of its inputs. A summary is
not automatically less sensitive than its source. Declassification must be an
explicit, reviewable action.

## Cloud-routing gate

A provider call is allowed only when all of the following agree:

```text
task allowed providers
meeting cloud-processing policy
input classification
user provider policy
provider data policy
```

A deny at any layer blocks the call. The application must show the route and
the exact bounded material before processing and retain the decision in task
history.

## Trust boundaries

- Imported documents, transcripts, web pages, metadata, subtitles, and
  media-derived text are untrusted data.
- Instructions embedded in source material cannot change application policy,
  tools, file access, provider routing, or destructive actions.
- Source content must be delimited as data in provider requests.
- Inference providers receive versioned semantic input packages, not direct
  database access or unrestricted paths.
- Agent-control adapters use the validated Automation Command Layer and remain
  separate from inference providers.
- Network-source adapters use HTTPS, an explicit domain allowlist, restricted
  redirects, content limits, and protections against local-network and file
  URL access.

## Credentials and local secrets

- API keys and tokens belong in macOS Keychain.
- Credentials never belong in source, `.env` files committed to Git, task
  directories, logs, diagnostics, exports, or crash reports.
- MeetingBuddy must not read or reuse credentials owned by another app.
- Subscription-backed clients must never be treated as APIs or used through
  extracted cookies, OAuth material, or undocumented protocols.

## Sandbox and local file authority

ADR-0002 Option A fixes the Task 005A authority boundary:

- `MeetingBuddyApp` declares App Sandbox, app-scoped security-scoped bookmarks,
  and user-selected read/write file access;
- the app persists exactly one bookmark for the user-selected MeetingBuddy
  workspace in its app preferences and retains that scope only while the
  workspace runtime is active;
- an invalid or unhealthy workspace selection is released and forgotten rather
  than retried silently on every launch;
- a user-selected media source receives transient scope through inspection and
  the Task-Manager-owned streamed copy/hash/registration operation;
- the source URL and source bookmark are never persisted in job payloads,
  checkpoints, SQLite, source metadata, logs, or preferences;
- the managed copy is re-inspected and must match the approved pre-copy
  inspection and byte size before a source revision is published;
- source and managed-file symlinks, traversal, mismatched hashes/sizes, and
  changed sources fail closed; partial cancelled copies are removed;
- no network-client, microphone, screen-recording, or application-audio
  entitlement exists in Task 005A.

The checked-in entitlement declaration and ad-hoc signed bundle verify the
approved capability set. A full-Xcode native run observed App Sandbox
initialization and its application container, presented the workspace Open
panel, persisted one app-scoped bookmark for a synthetic workspace, and
restored scoped authority after relaunch. The single importer is regression-
tested to route workspace and approved-media selections without retaining a
source bookmark. Developer ID and notarization remain Task 011 release gates.

## Logging, diagnostics, and telemetry

- Use structured `Logger`/OSLog-compatible logging with privacy annotations.
- Do not log credentials or complete sensitive meeting content by default.
- Bound and rotate logs; do not retain unlimited provider standard output.
- Telemetry and crash reporting are disabled until an ADR defines opt-in,
  redaction, retention, and vendor policy. Meeting content is excluded by
  default.

## External processes and files

Any approved external executable must use a narrow adapter with an explicit
path, validated argument array, bounded working directory, timeout,
cancellation, output limit, version check, and redacted diagnostics. Shell
interpolation of user or source content is prohibited.

File paths must be canonicalized and restricted to user-authorized roots.
Symlink and traversal escapes must be rejected.

## Destructive and sensitive actions

Deletion, original-media removal, Trash emptying, workspace moves, model
deletion, credential changes, restricted cloud processing, remote access, and
recording require direct confirmation appropriate to their risk.

## Task ownership

- Task 003A/003B: classification and provenance contracts.
- Task 004A/004B: safe storage, recovery, temporary data, and redacted logs.
- Task 005A: App Sandbox/file authority, transient source intake, native local
  media processing, and no-network/no-capture entitlement boundary.
- Task 005B: Keychain integration and enforced provider routing.
- Task 006A/006B: prompt isolation, claim/evidence validation, and safe output.
- Task 007: dedicated security, privacy, recovery, and failure hardening.
- Task 009A/009B: automation permissions and adapter security.

## Current implementation status

Tasks 003A and 003B implement the storage-neutral classification and provenance
contracts. Concrete objects fail closed on unsupported classification and
provenance values; pure resolved-object checks require every exact envelope
dependency to be supplied and reject derived objects that are less restrictive
than any of them. Transcript track kind,
translation source bytes, provider-neutral generation metadata, review state,
and user confirmation remain explicit. Synthetic source text is preserved as
untrusted data and is never interpreted as a control instruction by the
domain layer.

Task 004B adds local operational controls: job requests reject unknown or
unsafe classification/privacy routes and restricted cloud routes; task files
are confined to private job-owned directories with explicit budgets; structured
task logs remove private values, bound public values, redact common credential
patterns, rotate by size/count/age, and mark OSLog message text private. Job
failure records accept only bounded caller-declared safe summaries, while raw
diagnostics are private log values. No task test uses a provider or network.

Task 005A adds a local-only native app composition, the exact sandbox/file
entitlement declaration above, persistent workspace bookmark handling, and
transient source authority. Both source acquisition and canonical conversion
run through the single Task Manager; durable intake payloads contain only
bounded policy, technical metadata, and opaque IDs. AVFoundation diagnostics
are reduced to bounded safe summaries, while raw local framework errors remain
private task-log values.

No credential, Keychain, provider call, network call, microphone/screen/app-
audio permission, telemetry, or third-party crash-reporting runtime exists.
Cloud routing still requires the Task 005B application/provider gate; meeting
policy, job privacy route, and provider-usage fields do not authorize an
external call by themselves. The full-Xcode sandbox, workspace picker, and
bookmark-restoration gate passes using synthetic data; no provider or capture
authority was added.

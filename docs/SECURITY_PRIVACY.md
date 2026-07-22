# Security and Privacy Baseline

Status: Tasks 001 through 011 accepted; post-MVP evidence-integrity remediation
implemented locally; INTERNAL ALPHA distribution boundary
Owner: Codex
Last updated: 2026-07-22
Purpose: Define classification, routing, secret, logging, and trust-boundary
requirements. Provider details belong in ADRs and later implementation tasks.

## Data classification

All meeting audio, transcripts, metadata, and derived intelligence remain local
by default, including `public` data. Classification determines whether an
external exception can be considered; it never creates transmission authority.

Every source and derived semantic object must carry one classification:

| Class | Default processing rule |
| --- | --- |
| `public` | Local by default; cloud is permitted only through an explicit approved route and visible user authorization. |
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

Every external route must record:

```text
architectural policy decision and version
permitted provider
bounded data categories
destination and deployment environment
provider retention behavior
meeting sensitivity and organization policy
visible user authorization
offline/no-outbound alternative
```

An application-owned model-policy router enforces this intersection. Provider
or model selection UI is only a preference among eligible routes and cannot
override policy. Missing facts, policy denial, provider failure, or fallback
never weaken the route. Supported workflows retain a local/offline or no-
external-processing mode.

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
- Production secret access goes through an application-owned Secret Store port
  backed by macOS Keychain. There is no plaintext configuration fallback.

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

Task 008B later adds only audio input and network client authority for the
accepted audio-capture and exact-host UN Web TV metadata routes. The current
checked-in declaration and Task 011 bundle audit verify exactly five
entitlements: App Sandbox, app-scoped bookmarks, user-selected read/write,
audio input, and network client. Native runs verify sandbox initialization,
synthetic workspace bookmark restoration, purpose-routed import, and bounded
packaged-app launch. Task 011 confirms that Developer ID/Team ID,
notarization/stapling, and affirmative Gatekeeper distribution approval remain
absent.

## Logging, diagnostics, and telemetry

- Use structured `Logger`/OSLog-compatible logging with privacy annotations.
- Do not log credentials or complete sensitive meeting content by default.
- Bound and rotate logs; do not retain unlimited provider standard output.
- Telemetry and third-party crash reporting are disabled by default until a
  later ADR defines an opt-in destination, retention, operator, redaction, and
  user/organization policy.
- Telemetry never contains meeting audio, documents, transcript or derived
  content, API keys/tokens, meeting titles, filenames, sensitive paths, or
  identifiable meeting metadata.
- Telemetry can be fully disabled, is never required for normal operation, and
  respects no-outbound-network mode.
- Organization-controlled or self-hosted telemetry remains a separately
  approved future capability, not a Task 007 implementation assumption.

## Secure local data lifecycle

- Sensitive files use minimum necessary permissions and remain inside approved
  workspace/service boundaries.
- Exports are explicit, destination-scoped, classification-aware, and audited
  without silently uploading content.
- Retention and deletion behavior is documented per storage class. Workspace
  Trash is recoverable deletion, not a claim of forensic erasure.
- Secure-deletion guarantees must reflect APFS/SSD behavior; do not promise
  physical erasure without platform evidence.
- Application-level encryption requires a separate accepted ADR covering key
  storage, loss/recovery, rotation, backup, migration, and corruption.
- Task 011 audits signing and update boundaries. The current ad-hoc internal-
  alpha package has no Developer ID, Team ID, notarization ticket, approved
  automatic updater, or distributable update path.

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
- Task 006A: prompt isolation and claim/evidence validation.
- Task 006B: minimum semantic briefing inputs, deterministic coverage/
  validation, stale blocking, and explicit classification-aware local export.
- Task 007: model-policy, no-outbound, telemetry, encryption decision,
  retention/deletion, export hardening, long-transcript, and dedicated
  security/privacy/recovery hardening.
- Task 008A/008B: visible permissioned capture, incremental local persistence,
  incomplete-recording recovery, and device/interruption tests.
- Task 009A/009B: automation permissions and adapter security.
- Task 010: local historical reauthorization, evidence integrity, conservative
  comparison, and presentation-only preference boundaries.
- Task 011: accepted signed/update, migration, no-outbound, telemetry, security,
  and release audit; external distribution gates remain failed.

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
diagnostics are private log values. Its accepted tests use no provider or
network.

Task 005A adds a local-only native app composition, the exact sandbox/file
entitlement declaration above, persistent workspace bookmark handling, and
transient source authority. Both source acquisition and canonical conversion
run through the single Task Manager; durable intake payloads contain only
bounded policy, technical metadata, and opaque IDs. AVFoundation diagnostics
are reduced to bounded safe summaries, while raw local framework errors remain
private task-log values.

Task 005B implements the application-owned transcription/translation policy
router and records every decision in the manifest plus job provider usage. Its
production route is restricted to already-installed Apple Speech and
Translation models on this Mac. Requests explicitly carry classification,
offline mode, organization permission, environment, destination, retention,
bounded categories, visible authorization, and availability; a denied or
incomplete external candidate becomes manual-local or fails closed. There is
no Task 005B external adapter, URLSession/network implementation, model
download, provider credential, or outbound meeting-data transfer.

The production Secret Store uses macOS Keychain generic-password items and has
no plaintext fallback. A synthetic integration value round-trips and is
deleted; source/log/file scans find no credential literal or secret artifact.
The Apple route consumes only one task-owned local chunk or bounded transcript
text, providers cannot access SQLite/workspace roots, and task-owned audio is
removed after success/cancellation. Existing entitlements remain exactly App
Sandbox, app-scoped bookmarks, and user-selected read/write access; no network,
microphone, screen/app-audio, telemetry, or crash-reporting authority was
added.

The SwiftUI privacy card displays execution boundary, exact data categories,
destination, retention, application/organization policy authority, visible
user authorization, and decision reason before processing. macOS 15 through
25 or missing installed models retain the human-entered local transcript and
translation path. The full-Xcode Task 005A sandbox/bookmark evidence remains
the accepted native authority baseline.

Task 006A extends the same application-owned router with the `analysis`
capability and authorizes only Apple Foundation Models on the local device.
Automatic analysis requires macOS 26+, runtime availability, a supported
locale, an allowed local route, and the visible **Analyze Locally** action.
There is no Task 006A external provider, Private Cloud Compute path,
URLSession/network implementation, provider credential, model download,
telemetry, or new entitlement. When the local model is unavailable, automatic
creation remains unavailable and no source is sent elsewhere; existing local
analysis can still be inspected and corrected.

Each provider call uses a fresh no-tool session and receives one bounded,
versioned semantic package: reviewed transcript or translation text, exact
speaker/capacity context, classification, and opaque evidence identifiers.
The provider receives no SQLite handle, workspace root, file path, source
asset bytes, or unrestricted meeting corpus. Application-owned protected rules
delimit all source text as untrusted data, forbid outside knowledge and policy
changes, and constrain generation to a closed DTO. Provider output remains a
candidate until deterministic claim, evidence, actor/capacity, classification,
qualification, and complete-segment validation passes.

The route records exact data categories, local destination, visible
authorization, policy decision, prompt/rules/input hashes, runtime/model
evidence, and segment attempts. `noProviderRetention` applies to the provider
boundary; accepted derived revisions and coverage history remain durable under
the local workspace retention/recovery policy. Incomplete or invalid output is
stored only as bounded safe route/coverage failure evidence and publishes no
intelligence. The approved live check used only the project-authored versioned
synthetic fixture recorded in ADR-0010; no real meeting content was used.

Task 006B reuses that local-only policy boundary for three independent
briefing-section calls. The provider receives exactly validated intelligence
claim text and opaque evidence identifiers, never raw transcript, audio,
database access, workspace paths, tools, retrieval, or an unrestricted meeting
package. Source claims remain delimited untrusted data. A fresh no-tool guided
session, exact source-key closure, schema/byte limits, qualification retention,
and deterministic coverage/evidence/contradiction validation all fail closed.
No independent reviewing provider, external fallback, credential, dependency,
network implementation, model download, telemetry, or entitlement is added.

The post-MVP remediation in ADR-0017 treats structurally valid provider output
as quarantined rather than trusted. A provider `noSpeech` result can publish
only with application-owned exact-digital-silence confirmation over the exact
canonical core range. A provider `nonSubstantive` result can omit a segment only
when application code recognizes punctuation/symbol-only text or a closed
non-semantic marker and binds the exact segment revision and text digest.

Consequential analysis use requires explicit user confirmation of the exact
active candidate ledger ID, content hash, and every claim. Persistence rejects
confirmation if the candidate was superseded or if route, runtime, prompts,
inputs, eligible segments, or outputs differ. Briefing export separately
requires every current section and the final briefing to be user-created and
confirmed. These gates preserve accountability and provenance; they do not
claim that a human-confirmed statement is objectively true.

Task 009A adds only a local closed automation surface. Caller permission is a
trusted composition-root capability and cannot be raised through argv or a
command payload. Every accepted request claims a durable replay nonce before
execution, records actor/origin/permission/policy/revision metadata, and blocks
nested MeetingBuddy or inference-provider calls. Meeting-scoped status fails
closed unless the exact active/current published MeetingProfile,
SensitivityLabel, and AccessPolicy graph validates. Workspace commands are
content-free, local-only operations and record model routing as not applicable.

The CLI rejects confirmation, role, permission, and recursion flags. Export,
recording, provider/model work, credentials, access-policy changes, deletion,
arbitrary paths/SQL, network control, MCP, and HTTP remain unavailable. Audit
payloads contain bounded canonical metadata, opaque identifiers, digests, and
safe codes only; they exclude meeting content, filenames, raw argv, paths,
credentials, provider output, and raw errors. See
[`TASK_009A_AUTOMATION.md`](TASK_009A_AUTOMATION.md) and
[ADR-0014](adr/ADR-0014-task-009a-automation-command-boundary.md).

Task 010 history search is local and requires a current exact security graph at
both index construction and result hydration. The repository returns no content
or result count for a stale, missing, classification-exceeding, externally
permitted, or otherwise unsafe policy row. Rebuild requests are restricted,
local-only Task Manager jobs and add no provider, credential, subprocess,
listener, mail connector, or URLSession/network route.

Versioned-document, email-import, and public-source evidence contracts bind an
already-admitted exact `SourceAsset.v1` revision to SHA-256, byte size,
acquisition time, source kind, and remote-resource posture. These contracts do
not authorize reading a mailbox, opening an arbitrary file, browsing, or
fetching a URL. Imported text remains untrusted data. Comparison uses exact
Position/Evidence/security revisions and fixed qualified language; wording,
silence, and group membership cannot assert policy change. Only an explicit user
action can create a superseding confirmed comparison.

Learned preferences are explicit typed presentation values, not hidden memory.
They never alter classification, access policy, evidence closure, no-outbound
mode, provider/model routing, confirmation, or protected diplomatic rules.
Disabled values remain visible; remove/reset delete effective rows. Audit events
retain bounded action metadata and digests, not raw preference payloads. See
[`HISTORICAL_REVIEW.md`](HISTORICAL_REVIEW.md) and
[ADR-0016](adr/ADR-0016-task-010-historical-review-and-preferences.md).

All derived objects inherit the most restrictive input classification.
Markdown export is a separately explicit local action and requires the exact
active current valid `FinalBriefing.v1`, exact expected classification, a safe
workspace-confined filename, byte-integrity checks, private permissions,
different-file conflict refusal, and an immutable audit record. Stale content,
missing authorization, path escapes, symlinks, classification mismatch, and
invalid output are rejected without upload or overwrite. The installed-model
live check uses only bounded project-authored synthetic claims as recorded in
ADR-0011; no real meeting content is used.

Task 011 accepts the selected scope only as INTERNAL ALPHA. The new-scratch
242-test suite, supported migration/recovery matrix, tracked secret/container
scans, privacy/license resources, exact entitlements, idle socket inspection,
no-outbound/telemetry contracts, confined export/storage/retention tests, and
synthetic cold-backup checks pass. No real user workspace or meeting data was
read or changed.

External release remains blocked by missing Developer ID/Team ID,
notarization/stapling, affirmative Gatekeeper distribution approval,
clean-machine validation, manual accessibility/localization/icon review, and
intended-OS live TCC/capture evidence. The four medium evidence-integrity
findings that were open at Task 011 are addressed by the later ADR-0017
application-owned omission and exact human-confirmation gates; all derived
intelligence still requires careful evidence review.
Three low resource findings are mitigated in accepted source but await a
follow-up security scan. No tag, push, notarization submission, upload,
installation, or distribution is authorized or claimed.

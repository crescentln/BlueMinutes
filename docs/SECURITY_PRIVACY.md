# Security and Privacy Baseline

Status: Accepted policy baseline; enforcement is not implemented
Owner: Codex
Last updated: 2026-07-17
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
- Task 005B: Keychain integration and enforced provider routing.
- Task 006A/006B: prompt isolation, claim/evidence validation, and safe output.
- Task 007: dedicated security, privacy, recovery, and failure hardening.
- Task 009A/009B: automation permissions and adapter security.

## Current implementation status

Task 002 establishes policy only. No credential, provider, network, logging,
permission, entitlement, or telemetry implementation exists yet, so these
controls are not marked as passing.

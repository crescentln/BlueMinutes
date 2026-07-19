# Task 007 Hardening Report

Status: Completed pending user acceptance
Date: 2026-07-18
Scope: Reliability, privacy, storage, and quality hardening only
Rollback anchor: Git HEAD `2bcedea4132214ddc88486fb2c66f6030a87ed9f`

## Outcome

The implemented recorded-meeting vertical slice remains local-first and now
has exact sensitivity/access-policy revisions, a fail-closed model-policy
snapshot, default-disabled content-free telemetry, bounded storage accounting,
recoverable Trash, crash-safe permanent-unlink receipts, schema-v6 migration,
private SQLite sidecars, visible stale state, destructive confirmation, and
multi-hour coverage stress evidence.

No external provider adapter, telemetry destination, network client,
application-level encryption format, dependency, entitlement, live capture,
UN Web TV route, MCP surface, or automation authority was added. There is no
known P0 data-loss, privacy, or evidence-integrity defect in the implemented
vertical slice after the Task 007 gates below.

## Trust and data-flow boundary

1. A user-selected local file enters through a transient security-scoped
   authority and is copied, hashed, and registered into one private workspace.
2. Semantic revisions and exact dependency/active/stale state are authoritative
   in SQLite; large media remains hash-bound workspace files.
3. Task Manager jobs receive exact revisions, bounded task directories, disk
   budgets, local-only routes, checkpoints, and content-free public diagnostics.
4. Apple installed-model providers receive only the previously accepted bounded
   inputs. Imported text remains delimited untrusted data and no tool/retrieval
   authority exists.
5. Local export and permanent unlink are separate visible user actions. Export
   writes a private hash-verified file; unlink retains immutable audit history
   and never claims forensic erasure.

## Threat-model matrix

| Threat or abuse case | Boundary at risk | Implemented control and proof | Residual |
| --- | --- | --- | --- |
| Prompt-like transcript changes instructions or requests upload | Provider prompt boundary | Protected instructions are application-owned; source values are delimited untrusted data; malformed/invented keys and adversarial Golden cases fail closed | A future provider/prompt change requires renewed Golden and injection review |
| UI provider choice bypasses sensitivity, offline, organization, environment, destination, retention, or authorization | Model-policy router | Every new model job carries exact `SensitivityLabel.v1` and `AccessPolicy.v1` revision references; route matrix denies drift and legacy jobs remain local-only | No external adapter is authorized, so an otherwise allowed cloud route still fails closed |
| Classification is weakened downstream | Semantic graph and job boundary | Most-restrictive inheritance is deterministic and order-independent; request classification must equal its exact policy snapshot | Human misclassification at intake remains possible and visible for correction |
| Telemetry or logs leak content, credentials, titles, filenames, paths, or identifiers | Diagnostics boundary | Telemetry is disabled by default and its only implementation is a bounded in-memory fixed enum/counter schema; public logs use an allowlist and all other values redact | Local unified logging by Apple frameworks is outside MeetingBuddy's custom telemetry schema |
| Secret enters SQLite, files, or logs | Credential boundary | Keychain-only secret adapter, bounded opaque identifiers/values, negative secret/log fixtures, and no credential field in policy/job persistence | Compromise of the signed-in user or Keychain remains an OS/account threat |
| Crash between file deletion and metadata commit resurrects or loses state silently | Trash/filesystem/SQLite boundary | Durable purge intent precedes unlink; startup reconciles a missing file into an immutable receipt and never restores it; injected crash test passes | APFS/SSD/snapshots/backups prevent forensic-erasure claims |
| Early or accidental permanent deletion | Feature/application/storage boundary | At least 30-day Trash retention, visible confirmation, explicit unlink acknowledgment, exact item binding, and destructive-role UI | Task 007 does not add automatic scheduled purge |
| Broad permissions expose sensitive workspace bytes | Filesystem boundary | Workspace directories are `0700`; managed files, database/WAL/SHM, logs, exports, manifests, and recovery artifacts are `0600`; storage report surfaces drift | Root, malware running as the user, and copied unencrypted backups remain outside this control |
| Disk exhaustion causes partial publication or unbounded growth | Task/storage boundary | Capacity preflight runs before task-directory allocation; per-job byte/entry limits, bounded logs, bounded telemetry, bounded scans, and atomic publication remain enforced | Free space can change after preflight; a write may still fail and is handled as non-publication/retryable failure |
| Long transcript omits, duplicates, overlaps, or loses retry provenance | Transcript/coverage boundary | Three-hour/360-core test injects chunk 180 failure, starts a new manager, reuses verified checkpoints, completes exact traceability, and rejects omission/duplicate/overlap manifests | Bounded synthetic fixtures do not predict installed-model speed or accuracy on every Mac |
| Stale intelligence is exported as current | Dependency/UI/export boundary | Exact dependency traversal marks downstream state stale; analysis/briefing UI shows warnings and export validates the current active chain | A full one-click stale-chain regeneration flow remains future work |
| Migration corrupts accepted workspaces | SQLite migration boundary | Ordered migration 006 creates a verified online rollback backup, preserves v5 semantic payload bytes, validates schema/checksums, and rolls back injected failure | Downgrade requires restoring the backup; schema-v6 files are not claimed readable by older binaries |

## Quality-gate matrix

| Gate | Evidence | Result |
| --- | --- | --- |
| Debug and release compilation | `swift build --configuration debug -Xswiftc -warnings-as-errors`; same command with `release` | Pass |
| Ordinary suite | `swift test --enable-swift-testing --parallel -Xswiftc -warnings-as-errors` | 189 tests in 34 suites passed in 6.386 s; three explicit live Apple tests skipped by default |
| Security-policy contracts | Domain validation, canonical round-trip, exact revision persistence/activation/recovery, downgrade and no-outbound conflict tests | Pass |
| Route policy | Public/internal/sensitive/restricted local routes; offline/no-outbound, legacy, organization, environment, destination, retention, user authorization, unavailable-model cases | Pass; no external adapter authorized |
| Prompt injection | Protected analysis/briefing prompt tests, direct-decoder shape attacks, adversarial Golden source text | Pass |
| Keychain and secrets | Keychain round-trip/removal; invalid identifiers; empty/oversized values; secret-pattern/source/workspace/log scans | Pass; no secret artifact found |
| Logs and telemetry | Bounded log rotation/retention, strict public allowlist, negative content fixtures, disabled/default/no-outbound telemetry schema | Pass |
| Storage/Trash/deletion | Bounded dashboard scan, category visibility, permission-drift fixture, 30-day retention, restore, unlink receipt, crash recovery, no resurrection | Pass |
| Export | Explicit authorization, active/non-stale/classification checks, path confinement, atomic private `0600` output, hash and audit idempotency | Pass |
| Disk full/capacity | Injected 1,024-byte capacity rejects a 1,025-byte lease before directory creation; task over-budget tests remain green | Pass |
| Provider failure/cancel/restart | Transcript, analysis, and briefing failure produces incomplete coverage and no partial semantic publication; cancel/retry/startup tests remain green | Pass |
| Long meeting and coverage | Three-hour/172,800,000-frame, 360-core failure at core 180, manager restart, retry, exact source traceability, omission/duplicate/overlap rejection | Pass in 5.409 s on this host |
| Golden | Existing five diplomatic fixtures plus prompt-injection and explicit non-decision/non-commitment cases | 7 of 7 contract fixtures pass; Task 006A deterministic rubric remains 5 of 5 |
| Migration/recovery | Fresh and accepted v1-v2-v3-v4-v5 to v6, byte preservation, unknown future rejection, injected rollback, recovery snapshot, close/reopen | Pass |
| Storage growth | 96-file growth fixture, 32-entry scan bound, truncation visibility, category totals, private-permission detection | Pass; production UI scan bound is 100,000 entries |
| Accessibility/keyboard | Source-structural tests for Command-O, Command-I, Command-Return, Command-Shift-R, progress label/value, stale warning, destructive confirmation and hints | Pass; manual assistive-technology usability remains a release review item |
| Dependency/license | Exact dependency graph, resolved revision, local license/privacy manifest, import confinement, official release/advisory review | GRDB 7.11.1 only; MIT; no published repository advisory or matching GitHub advisory found at review time |

## No-outbound and diagnostic evidence

- A production-source scan found no `URLSession`, `URLRequest`, Network
  framework, WebSocket, socket-connect, or DNS-resolution implementation.
- The ad-hoc signed sandboxed app launched successfully and remained running for
  54 seconds with zero process-owned Internet sockets in two `lsof` queries.
- App entitlements remain App Sandbox plus user-selected read/write and
  app-scoped bookmark authority; there is no network client/server entitlement.
- The only Task 007 telemetry recorder owns no URL, socket, file, provider, or
  upload surface. Default policy suppresses events; opt-in local diagnostics
  holds at most 4,096 fixed-schema events in memory.
- Task logs default to 4 MiB, eight archives, and 14-day retention. Public
  strings outside the fixed allowlist become a redaction marker; private values
  never enter the persisted message.

This evidence applies to the implemented MeetingBuddy code and tested local
path. It is not a packet-capture claim about unrelated OS daemons, future
provider adapters, or future release builds.

## Storage, deletion, and recovery behavior

- Storage is reported by category without displaying filenames or sensitive
  paths. A scan that reaches its configured bound is visibly incomplete rather
  than silently green.
- Trash items expose opaque managed IDs, size, classification, retention class,
  and the exact purge-eligible time. Restore remains available before unlink.
- Permanent deletion validates exact item identity, visible confirmation,
  minimum retention, and the explicit method
  `filesystem_unlink_no_erasure_guarantee`.
- The operation writes durable intent before filesystem mutation and an
  immutable receipt after unlink. Startup recovery decides from file presence
  and recorded hashes; an absent verified Trash file is finalized, never
  resurrected.
- Semantic history, audit receipts, migration backups, external copies,
  snapshots, and physical flash cells are not deleted by the unlink operation.

## Encryption decision

[ADR-0012](adr/ADR-0012-task-007-workspace-encryption-boundary.md) rejects an
application-level encrypted format for this single-user local milestone. It
avoids introducing an unproven key-loss/rekey/backup/migration failure mode and
preserves independently readable recovery artifacts. Keychain remains the only
credential store; host/account and volume encryption remain operator controls.

## Dependency and license inventory

- Direct/transitive package graph: GRDB 7.11.1 only, revision
  `b83108d10f42680d78f23fe4d4d80fc88dab3212`.
- License: MIT; checked-out license SHA-256
  `9853f9dce81365fcc1d9b46004633354450164b8d17904e92e80c444545f7e87`.
- Official release: <https://github.com/groue/GRDB.swift/releases/tag/v7.11.1>.
- Repository advisories: <https://github.com/groue/GRDB.swift/security/advisories>.
- GitHub Advisory Database query:
  <https://github.com/advisories?query=GRDB.swift>.
- Detailed lifecycle note: [dependencies/GRDB.md](dependencies/GRDB.md).

The absence of a published advisory is point-in-time negative evidence, not a
guarantee of vulnerability absence. Eventual application notices must include
the MIT license.

## Compatibility and rollback

- The compatible feature rollback is to disable telemetry/providers and leave
  the stored local contracts readable; no data must be deleted to disable a
  feature.
- Migration 006 uses a pre-migration online SQLite backup. To run an older
  binary, close MeetingBuddy and restore that verified schema-v5 backup rather
  than opening schema v6 in place.
- Unaccepted Task 007 source/test/doc changes can be removed relative to Git
  anchor `2bcedea4132214ddc88486fb2c66f6030a87ed9f` only with a targeted,
  user-authorized revert that preserves the unrelated pre-existing dirty
  documentation edits.
- A completed permanent unlink cannot be rolled back from the primary
  workspace. Before retention expiry, use Restore; afterward, recovery depends
  on a separately retained backup and is not guaranteed.

## Residual risks and deferred gates

- Application-level workspace encryption is intentionally absent; an
  unencrypted volume, compromised signed-in session, root, or same-user malware
  remains outside the app's POSIX boundary.
- The ordinary suite does not run the three opt-in installed Apple model tests.
  Their output quality and latency can vary with host OS/model updates and must
  be revalidated for release.
- No automatic Trash purge scheduler exists. The implemented action is manual,
  visible, retention-gated, and recoverable before unlink.
- Storage accounting is bounded rather than a full forensic inventory; the UI
  marks truncation.
- Manual VoiceOver, Voice Control, Switch Control, reduced-motion/contrast,
  localization, and clean-machine usability review remain release evidence,
  despite the compiled labels, hints, values, keyboard shortcuts, and
  structural tests.
- Developer ID, notarization, final privacy-manifest merge, license-notice
  packaging, update-path security, and clean-machine validation remain Task 011.
- Live capture, UN Web TV, external providers, organization telemetry, MCP,
  automation, historical knowledge, and broad UI redesign remain excluded.

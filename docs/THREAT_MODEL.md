# Threat Model

Status: living security document
Last updated: 2026-07-22

## Scope

This threat model covers the local macOS application, Swift packages, selected
user workspace, SQLite metadata, managed media, AI provider adapters, Task
Manager, local automation and MCP surfaces, exports, backups, and source
repository. It does not certify the application for classified, legally
privileged, export-controlled, or institutionally restricted material.

## Security objectives

- Preserve the confidentiality and integrity of meeting material and
  credentials.
- Keep processing local unless an explicit approved route authorizes bounded
  external data categories.
- Preserve exact provenance, immutable revisions, coverage, uncertainty, and
  evidence links.
- Prevent provider output from silently becoming trusted fact or authorizing
  source omission.
- Preserve user control over confirmation, export, deletion, recovery, and
  external processing.
- Fail closed when authority, schema, coverage, currentness, or integrity cannot
  be proven.

## Protected assets

- Original audio, video, documents, transcripts, translations, and speaker
  assignments.
- Derived positions, commitments, decisions, briefing text, and historical
  comparisons.
- Evidence references, content hashes, coverage manifests, review state,
  active-revision pointers, and audit events.
- User workspaces, SQLite databases, backups, exports, logs, and task state.
- API credentials, access tokens, bookmarks, signing identities, and
  notarization material.
- Source code, dependencies, CI configuration, release provenance, and
  maintainer authority.

## Trust boundaries

1. **Imported content:** media, documents, transcripts, subtitles, metadata,
   web content, and excerpts are untrusted data.
2. **Provider boundary:** AI providers receive only bounded, policy-approved
   packages and return untrusted structured output. They never query SQLite or
   receive an unrestricted workspace.
3. **Application boundary:** application-owned validation, provenance,
   classification, Task Manager, and Storage Service gates mediate all durable
   effects.
4. **Human-review boundary:** consequential analysis and exported briefing text
   require explicit review bound to exact immutable revisions.
5. **Filesystem boundary:** persistent writes are confined to the selected
   workspace or explicit user export path; transient source authority is not
   persisted.
6. **Automation boundary:** local CLI/MCP commands use bounded allowlisted
   application services and do not inherit provider authority.
7. **Repository/CI boundary:** public source, Issues, Pull Requests, CI, and
   fixtures must contain no real meeting material, credentials, or user data.

## Threats and controls

| Threat | Primary controls |
| --- | --- |
| Prompt injection in imported material | Source content is delimited and treated as data; it cannot change policy, tool authority, routes, or destructive actions. |
| Schema-valid fabricated analysis | Provider candidate remains quarantined; consequential use requires explicit confirmation bound to the exact active ledger ID, content hash, timestamp, and all candidate claims. Persistence rejects forged or stale confirmations. |
| Fabricated briefing text with valid source keys | Generated sections remain reviewable; export requires every section and the final briefing to be user-created, confirmed, valid, current, and active. |
| Provider falsely marks speech as absent | A provider `noSpeech` result publishes only when the application verifies exact zero-valued 16-bit mono 16 kHz PCM across the exact owned core range. Anything else fails closed for review. |
| Provider omits meaningful transcript or translation as non-substantive | Omission is allowed only when the transcript and any translation both contain punctuation/symbol-only text or a closed non-semantic marker. The confirmation binds the exact revisions and text digests; meaningful or changed text fails closed. |
| Stale or substituted evidence | Immutable revisions, content hashes, exact active pointers, dependency invalidation, and source-range coverage reject stale or mismatched chains. |
| Direct provider access to data stores | Provider interfaces receive bounded requests; providers have no SQLite table access or unrestricted filesystem path. |
| Unauthorized cloud disclosure | Local-only default, classification inheritance, no-outbound mode, route-policy intersection, visible authorization, and no silent fallback. |
| Credential disclosure | macOS Keychain only; no plaintext fallback; redacted bounded logs; secret and history scans before publication. |
| Filesystem traversal or symlink escape | ID-based Storage Service, canonical path confinement, symlink/traversal rejection, private permissions, atomic writes, and explicit destinations. |
| Crash, interruption, or partial long-running work | Single Task Manager, durable checkpoints, bounded temporary storage, recovery reconciliation, incomplete-state visibility, and fail-closed publication. |
| Migration corruption or downgrade loss | Ordered migrations, transaction rollback, verified pre-migration backups, supported-prior-state tests, integrity checks, and restore-to-new-path rollback. |
| Destructive automation or confused deputy | Separate allowlisted Automation Command Layer, explicit policy/confirmation, audit attribution, no arbitrary SQL or filesystem authority. |
| Supply-chain or release compromise | Exact Swift dependency pin, license/security review, minimum CI permissions, manual dependency review, protected `main`, reproducible checks, and separate signing/release authorization. |

## Evidence-integrity publication states

```text
provider output
  -> structurally valid immutable candidate
  -> application-owned coverage checks
  -> quarantined analysis review
  -> explicit exact-ledger human confirmation
  -> generated briefing sections
  -> explicit confirmation of every section and final
  -> current, classification-checked local export
```

No state transition is evidence that a generated claim is objectively true.
Human reviewers remain responsible for comparing claims with linked source
evidence and organizational policy.

## Residual risk

- Exact-digital-silence verification is intentionally conservative. Ordinary
  room tone is not automatically classified as no speech and requires review.
- The closed non-semantic marker list can create false negatives, but meaningful
  text is not automatically omitted.
- An authorized human reviewer can still make a substantive mistake or confirm
  too broadly. The system preserves the exact review boundary and evidence; it
  does not replace professional judgment.
- Compromised local accounts, operating systems, input devices, or approved
  providers are outside complete application control.
- The current internal alpha has no application-level workspace encryption,
  Developer ID distribution proof, notarization, or approved automatic update
  path.
- Open source enables independent inspection but does not guarantee security.

## Verification and reporting

Security changes require focused regression tests, the full warning-as-error
build/test gate, a sensitive-data and secret audit, and review of persistent
data and rollback impact. Use `SECURITY.md` for private vulnerability reporting
and never attach real meeting material or credentials.

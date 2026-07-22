# ADR-0017: Evidence-integrity publication boundaries

Status: Accepted under the authorized post-MVP security-remediation task
Date: 2026-07-22

## Context

The accepted Task 011 security audit identified four medium findings:

1. structurally valid provider analysis could become active without semantic
   grounding or a binding human-review boundary;
2. briefing text with valid source keys could reach export without confirming
   that its prose was supported;
3. provider-only `nonSubstantive` classifications could omit meaningful
   transcript segments; and
4. provider-only `noSpeech` classifications could omit spoken audio ranges.

Automatic semantic entailment is not reliable enough to establish diplomatic
truth. Provider self-assessment is not an independent control. The project
needs conservative, auditable transitions that preserve existing immutable
history and schema-v10 workspaces.

## Decision

### Transcript no-speech

A provider result cannot by itself close a canonical audio range. Production
publication requires an application-owned confirmation over the exact core
range. Version 1 recognizes only exact zero-valued PCM in the deterministic
16-bit mono 16 kHz canonical format. Malformed, non-zero, unavailable, or old
unconfirmed results fail closed and remain reviewable.

### Analysis omissions

A provider result cannot decide that meaningful transcript text is
non-substantive. Version 1 permits omission only when application code verifies
punctuation/symbol-only text or one exact member of a closed conventional marker
set. The immutable confirmation binds the transcript revision, SHA-256 digest
of the exact source text, and—when present—the translation revision and exact
translated-text digest, plus the method and verifier version. Both texts must
pass the same closed policy. The persisted reason is application-owned rather
than provider-authored.

### Analysis review

A structurally valid analysis publication is an immutable quarantined
candidate. Consequential downstream use requires a new immutable ledger whose
confirmation binds the exact active candidate ledger ID, content hash,
confirmation time, and all claims. Persistence verifies that the candidate is
still active and that route, runtime, prompts, inputs, eligible segments, and
claim references are unchanged. Position correction and briefing creation
require the confirmed ledger.

### Briefing review and export

Generated briefing output is review material. A final briefing is
human-confirmed only when all three exact current sections and the resulting
final are user-created, confirmed, valid, active, and not stale. Local Markdown
export rechecks this state, classification, and exact final revision before any
file write.

### Compatibility

No SQLite schema migration is introduced. New confirmation fields are encoded
inside existing versioned payloads and decode as optional for historical
records. Historical objects remain immutable and readable, but legacy
provider-only omission records cannot satisfy the new downstream publication
gates. Confirmation creates superseding immutable ledgers or revisions rather
than rewriting prior bytes.

## Consequences

- False-negative automation is accepted in favor of silent source omission.
- Ordinary acoustic silence and unrecognized stage directions require manual
  review.
- Human review is explicit and auditable but can still be mistaken; this ADR
  does not claim automatic truth verification.
- Existing schema-v10 workspaces remain openable without migration.
- Analysis confirmation currently covers the exact candidate as a whole. A
  future per-claim workflow would require a new ADR and compatibility plan.
- Focused transcript, analysis, briefing, provider, persistence, and full-suite
  regression tests are required for changes to these gates.

## Alternatives considered

- **Trust the provider's classification:** rejected because it is the same
  authority whose output is under review.
- **Use a second model as reviewer:** rejected as an insufficiently independent
  truth boundary and an expansion of provider, privacy, and cost scope.
- **Heuristic acoustic silence threshold:** rejected for version 1 because
  threshold choices can silently erase quiet speech.
- **Rewrite or delete historical ledgers:** rejected because it breaks
  immutability, auditability, and backward compatibility.
- **Block all generated output permanently:** rejected because explicit
  evidence-linked human review provides a controlled useful path.

## Rollback

The source rollback anchor is the pre-remediation `main` commit
`5450a916172c07ec2b7054c76fa40c80db17692e`. Code rollback must not delete or
rewrite any newer workspace record. Because older code does not understand the
new review semantics, operational rollback uses a verified pre-change cold
workspace backup restored into a distinct path.

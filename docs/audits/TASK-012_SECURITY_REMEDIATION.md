# Task 012 Evidence-Integrity Security Remediation

Status: implemented and locally verified; BlueMinutes selected as the public
brand; reachable `main` history sanitized; GitHub publication pending the exact
commit, identity-metadata, remote, public-CI, and visibility gates
Date: 2026-07-22
Rollback anchor: `5450a916172c07ec2b7054c76fa40c80db17692e`

## Scope

This follow-up addresses the four medium findings preserved in the immutable
Task 011 security scan. It adds no product feature, external provider, network
route, dependency, SQLite schema migration, release, or public repository.

## Finding disposition

| Task 011 finding | Remediation | Local regression evidence |
| --- | --- | --- |
| Provider-only `noSpeech` could close transcript coverage | Production application verifier accepts only exact digital silence across the exact deterministic core range; confirmation is persisted and required for new publication and downstream analysis. | Provider-only omission fails; exact-zero PCM passes; one non-zero sample fails; checkpoint restore cannot revive an unconfirmed legacy result. |
| Provider-only `nonSubstantive` could omit eligible analysis text | Closed application-owned marker/punctuation policy binds exact transcript and optional translation revisions and text digests; meaningful language fails closed. | Provider-only meaningful omission fails; a closed marker passes; meaningful or changed transcript/translation text is rejected. |
| Structurally valid analysis could become consequential without semantic grounding | Provider analysis is quarantined until a user confirms the exact active ledger ID/hash and every claim; persistence rejects stale, substituted, partial, or forged confirmation. | Unconfirmed analysis cannot drive correction or briefing; exact confirmation supersedes immutably; forged/stale confirmation fails. |
| Source-key-valid briefing prose could be exported without grounding | Every section and final must be user-created and confirmed; export rechecks active/current/valid state, classification, and exact final revision. | Unconfirmed export is rejected without creating an export record; fully confirmed synthetic fixture exports exact expected bytes. |

## Compatibility and storage

- SQLite remains schema version 10.
- New confirmation data is optional when decoding historical payloads, so old
  records remain readable.
- Historical provider-only omission records remain immutable but cannot satisfy
  the new downstream publication boundary.
- Confirmation creates superseding immutable analysis ledgers and briefing
  revisions; it does not alter prior semantic-object bytes.
- No user workspace or real meeting content was used.

## Verification completed

Focused suites passed:

```sh
swift test --filter TranscriptPipelineIntegrationTests
swift test --filter AnalysisPipelineIntegrationTests
swift test --filter BriefingPipelineIntegrationTests
swift test --filter ProviderContractTests
```

The warning-as-error build and complete post-brand local suite also passed: 248
tests in 43 suites, zero failures, with three installed Apple-model tests
skipped by their explicit opt-in gate. Local YAML parsing, Issue-form structure,
Dependabot-ecosystem, minimum-CI-permission, pinned-action, no-secrets, and
no-signing/release/deployment policy checks pass. Reachable `main` history and
the intended worktree contain no private local account path. An offline
detect-secrets 1.5.0 scan was run and all candidates were reviewed as
synthetic fixtures, enum labels, or expected digests. The final intended-diff
pre-commit gate passes; the same checks and public CI remain required on the
exact committed revision.

## Residual risk

- Human confirmation is an explicit accountability boundary, not proof of
  objective truth.
- Exact digital silence and the closed marker set intentionally prefer manual
  review over aggressive omission.
- The historical Task 011 scan remains immutable. This document and
  ADR-0017 record the later remediation; a review of the complete publication
  diff remains required before closure.

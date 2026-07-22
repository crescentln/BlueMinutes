# Task 011 Verification Evidence

Recorded: 2026-07-22T01:35:57Z
Release classification: **INTERNAL ALPHA**
Distribution authorization: none

## Evidence binding

The ignored local release set is
`dist/MeetingBuddy-0.1.0-internal-alpha/`. Its
`release-manifest.json` records:

- Git HEAD `2a0d7fe7ac8ab10d125f3c65b6606238e4df9343`;
- source state `dirty`, because Task 011 remains intentionally uncommitted;
- 189 build, test, configuration, notice, and script files in
  `source-files.sha256`;
- source-inventory SHA-256
  `ed9983486f217bd6274ceb97dc324d7b9547ffae2daba32ef44e8942ff059e5b`;
- `Package.resolved` SHA-256
  `a14ed642cc66bd9ebdfcbfc4f23886a78afa0663d97e5243848bf77fbb688e26`;
- Swift 6.3.3, Xcode 26.6, macOS 26.5.2, and arm64; and
- an explicit `INTERNAL_ALPHA`, `distribution_authorized=false`, ad-hoc,
  not-submitted-for-notarization classification.

The source inventory binds the source and tests used to build the artifact.
The packaging script computed it both before and after the release build and
also proved that scoped Git status and HEAD remained unchanged. It is not a
substitute for an accepted clean Git revision or a signed provenance service.

## Automated test gates

The final full command used a new `/tmp` SwiftPM scratch directory:

```bash
swift test --scratch-path <new-temporary-directory> \
  -Xswiftc -warnings-as-errors
```

Result: **242 tests in 42 suites passed** in 33.752 seconds. The three
installed-model tests were truthfully skipped in this ordinary run. Notable
measurements were:

- 10,000 published Positions: 9.081141167-second rebuild and
  0.319461-second first filtered page;
- three-hour transcript retry across manager restart: 5.952 seconds; and
- the new malformed blocked-HTML and independent cold-workspace restore/reopen
  regressions both passed.

The installed-model group then ran separately against synthetic-only content:

```bash
MEETINGBUDDY_RUN_LIVE_APPLE_MODELS=1 \
MEETINGBUDDY_RUN_LIVE_APPLE_ANALYSIS=1 \
MEETINGBUDDY_RUN_LIVE_APPLE_BRIEFING=1 \
swift test --scratch-path <new-temporary-directory> \
  -Xswiftc -warnings-as-errors --filter AppleProviderLiveTests
```

Result: **3 tests in 1 suite passed** in 6.016 seconds: speech/translation in
2.415 seconds, analysis in 2.634 seconds, and briefing in 0.966 seconds.

## Packaging and runtime gates

`script/package_release_candidate.sh` completed a new-scratch release build
and both staged and final release-set verification. The verifier also expanded
the ZIP into a fresh temporary directory and reverified the extracted app.

- Executable: 25,170,800 bytes; SHA-256
  `fcf52a3ca6547a801475f579e8d15da7143c068dd4c8c653cc47c7805e5bad83`
- Code-directory hash: `abc234e513301bdf45af420595918ac280dc414a`
- App allocated size: 24,608 KiB
- ZIP: 6,704,678 bytes; SHA-256
  `2ae023748b20f0bcf3c5dba87a839948248ff5edc914015020ade5ee50b12f44`
- Release-set allocated size: 31,188 KiB
- Architecture: one arm64 slice; system dynamic libraries only
- Signature: ad-hoc with Hardened Runtime and the exact five reviewed
  entitlements

Positive checks covered the closed bundle/release-set/ZIP-root allowlists,
privacy and license resources, source/build manifest binding, ZIP digest,
exact entitlements, strict signature integrity, architecture, and dynamic
dependencies. Internal mode requires `INTERNAL_ALPHA` and
`distribution_authorized=false`; distribution mode requires the separately
reviewed release classification and authorization. Negative probes proved
that distribution mode rejects the ad-hoc signature, an extra release-set
entry fails the closed layout, and a hash/manifest-rebound ZIP with an extra
top-level sibling fails the extraction-root allowlist.

The three Task 011 scripts use the fixed macOS system `#!/bin/bash`
interpreter. Earlier direct executions through `#!/usr/bin/env bash` were
terminated by this host's provenance enforcement; those failed attempts never
published staged output. The final direct packaging invocation completed all
staged, extracted, and final verification gates.

The final packaged app launched from the final path, held no idle network
socket or meeting-workspace content file, and exited after `TERM`. This is a
bounded idle check, not full-workflow packet evidence.

Distribution gates remain failed: zero valid signing identities, no Team ID,
no stapled notarization ticket, `syspolicy_check distribution` failure, and no
affirmative `spctl` acceptance. No notarization request was submitted.

## Backup and rollback gates

`script/verify_workspace_backup.sh` passed on a disposable cold synthetic
workspace and independent `ditto` copy. It verified exact content and metadata
inventories, BSD flags, xattrs, independent file identities, SQLite checks,
ownership, ACL absence, and owner-only usable permissions. It recomputed the
content, metadata, and xattr inventories at the end and proved both trees were
unchanged. It then rejected:

- a backup file hard-linked to the source; and
- a read-only backup file; and
- a backup entry with a mismatched immutable BSD flag.

The full Swift suite separately copied a real application-created schema-v10
synthetic workspace, reopened the copy through `LocalWorkspaceService` and
`SQLitePersistenceStore`, verified schema/quick/foreign-key state, and proved
the copied database had a distinct file identity. All disposable shell
fixtures and scratch directories were moved to macOS Trash after validation.
No real user workspace or meeting content was touched.

The verifier takes no OS-level lock. It therefore requires MeetingBuddy to
remain quit for the entire cold copy and verification; the final inventory
pass detects observed mutation but is not a substitute for that operational
boundary.

## Security and review result

The sealed standard scan `ec5ba727-af63-4f1a-bd8c-feb3001ed3a2` completed
134/134 work rows and remains immutable at four medium and three low findings.
The post-scan source mitigates the three low resource paths and adds two
correctness controls, but formal finding closure requires an accepted revision
and follow-up scan. Four medium evidence-integrity findings remain open.

Independent read-only packaging, release-gate, security-preflight, and threat-
model reviews agreed that the artifact must remain local **INTERNAL ALPHA** and
must not be described as a distributable release candidate.

The twenty pre-existing dirty governance/architecture/ADR files remained
untouched. Three of them still contain pre-Task-011 status or 236-test text;
the execution ledger and dedicated Task 011 audit are the current authorities
until those preserved edits receive separate reconciliation authority.

One earlier focused run against the repository `.build` directory was stopped
after a host child-process/file-handle stall. Fresh `/tmp` scratch reruns passed
and are the evidence reported above; the stalled run is not counted as a pass.

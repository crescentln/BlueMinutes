# Task 011 Release-Candidate Audit

Status: Accepted
Release classification: **INTERNAL ALPHA**
Selected product: `MeetingBuddy.app` for Apple Silicon, macOS 15 or later
Audit date: 2026-07-21
Pre-task rollback anchor: `2a0d7fe7ac8ab10d125f3c65b6606238e4df9343`

## Decision

The selected application scope is coherent enough for local internal-alpha
evaluation, but it is not a release candidate and must not be published or
distributed. The package is a thin arm64 macOS app with an ad-hoc Hardened
Runtime signature. This host has no valid code-signing identity; the app has no
Developer ID signature, Team ID, notarization ticket, or clean-machine proof.
Four medium evidence-integrity findings also remain open at the provider-to-
publication boundary.

The CLI and local MCP executables remain tested developer/operator products.
They are not embedded in or distributed with the selected app bundle.
Automatic updates remain unapproved under ADR-0002. Task 011 produces a
hash-bound manual-update archive only; it does not install, publish, upload,
notarize, or distribute that archive.

## Exact release artifact

- Coherent release set: ignored local output
  `dist/MeetingBuddy-0.1.0-internal-alpha/`
- Bundle: `dist/MeetingBuddy-0.1.0-internal-alpha/MeetingBuddy.app`
- Archive:
  `dist/MeetingBuddy-0.1.0-internal-alpha/MeetingBuddy-0.1.0-internal-alpha.zip`
- Archive SHA-256:
  `2ae023748b20f0bcf3c5dba87a839948248ff5edc914015020ade5ee50b12f44`
- Executable SHA-256:
  `fcf52a3ca6547a801475f579e8d15da7143c068dd4c8c653cc47c7805e5bad83`
- Code-directory hash:
  `abc234e513301bdf45af420595918ac280dc414a`
- Executable bytes: `25,170,800`
- Bundle allocated size on the audit host: `24,608 KiB`
- Archive bytes: `6,704,678` (`6,547 KiB` rounded down)
- Whole release-set allocated size on the audit host: `31,188 KiB`
- Architecture: one `arm64` slice
- Minimum OS declaration: macOS `15.0`
- Build host: Apple M4, 16 GB, macOS 26.5.2, Xcode 26.6, Swift 6.3.3
- Source inventory: 189 build/test/configuration/notice/script files;
  SHA-256
  `ed9983486f217bd6274ceb97dc324d7b9547ffae2daba32ef44e8942ff059e5b`

The archive was expanded into a new temporary directory and the extracted app
passed the same signature, architecture, dependency, entitlement, privacy,
license, and closed bundle-layout verifier as the source app. The app, ZIP,
digest, source inventory, and source/build manifest are staged and verified as
one coherent directory set, then recoverably replace the prior set. Acceptance
fails on mixed components. Replacement uses two renames rather than a strict
atomic directory exchange, so interruption can leave a `.previous-*` set that
requires manual inspection. The artifact was built before acceptance from an
uncommitted Task 011 working tree; its manifest records that dirty state and
the exact file hashes. Task 011 is now accepted locally, but this artifact is
not a publication candidate until a separately authorized, reproducible signed
build is made from the accepted revision. Detailed command evidence is in
`docs/audits/TASK-011_VERIFICATION_EVIDENCE.md`.

## Task 011 hardening

The audit made five bounded changes without reopening accepted feature scope:

1. Canonical chunk planning fails before allocation above the tested three-hour
   (`172,800,000` frame) release bound.
2. Media inspection accepts at most 32 audio tracks and rejects excessive
   cardinality before per-track metadata loading, sorting, or UI population.
3. Local media intake enforces the inspected byte ceiling inside the streamed
   copy loop before writing a chunk that would cross the ceiling; failed copies
   roll back their operation intent and remove owned staging bytes.
4. UN Web TV blocked-element removal now advances monotonically through each
   immutable input string instead of repeatedly rescanning and mutating the
   whole prefix; an unclosed blocked element fails closed as parser drift.
5. Recording persistence refuses to restore a recovery outcome that still has
   quarantined bytes or a checkpoint marked `reconciliationRequired`.

No database schema, provider, model, credential, entitlement, network
destination, automatic updater, or feature route was added.

## Quality-gate matrix

| Gate | Result | Evidence and limitation |
|---|---|---|
| Accepted prerequisites | PASS | Tasks 001 through 011 are accepted. |
| Debug build and full tests | PASS | New-scratch `swift test -Xswiftc -warnings-as-errors`: 242 tests, 42 suites, zero failures; three explicitly opt-in model tests are skipped in the ordinary run. |
| Installed Apple provider smoke tests | PASS | Three opt-in, synthetic-only local tests passed in 6.016 seconds: speech/translation, analysis, and briefing. Provider success does not close semantic-grounding findings. |
| Golden fixtures | PASS | Seven unique synthetic quality cases, canonical contract graphs, exact evidence references, adversarial negation preservation, and the 5/5 diplomatic rubric pass. |
| Long meeting and retry/restart | PASS | The synthetic three-hour checkpoint and manager-restart traceability test passes with exact coverage. |
| Transcript structural coverage | PASS | Omission, duplicate, overlap, retry, restart, cancellation, stale-input, and failed-publication tests fail closed. Provider-only `noSpeech` remains a separate medium finding. |
| Analysis/briefing evidence integrity | FAIL | Structurally valid provider output can still be published without application-owned semantic entailment; source-key-only briefing grounding and provider-only omission classifications remain open P2 findings. |
| Recording durability | PASS (automated) | Incremental sealing, process restart, damaged segment quarantine, finalization restart, provider loss, disk budget, cancellation, and device-reselection contracts pass. Live physical TCC/device-loss/sleep/power-loss testing is not complete. |
| Fresh schema and migrations | PASS | Fresh v10 creation, supported v1-v9 upgrades, unknown-future rejection, verified pre-migration backups, injected failure, quick-check, foreign-key, and recovery tests pass. |
| User-data backup/restore | PASS (synthetic) | A cold whole-workspace copy passed exact content/metadata/xattr/BSD-flag inventory, independent-inode, permissions/ACL, source/backup SQLite, and unchanged initial/final inventory checks. BSD-flag-mismatched, hard-linked, and read-only copies were rejected; an application-created copied workspace reopened through the production workspace/store path. The verifier takes no OS-level lock, so MeetingBuddy must remain quit. No real user workspace was read or changed. |
| Clean release build | PASS | `package_release_candidate.sh` used a new SwiftPM scratch directory and exact GRDB 7.11.1 resolution, built with warnings as errors, proved the scoped source inventory, HEAD, and Git status stayed stable across the build, and recoverably replaced one coherent release set. |
| Clean-machine install | NOT TESTED | No separate clean macOS machine or fresh user account was available. |
| Bundle layout/resources | PASS | Closed app/release-set and ZIP extraction-root allowlists, Info.plist, app privacy manifest, GRDB resource bundle/privacy manifest, MIT notice, and code-signature resources are present and sealed; release-set extra-entry and ZIP-root sibling negative probes failed as required. |
| App icon/localization polish | FAIL | No approved `.icns`/asset catalog and no localized `.strings` resources exist; the bundle uses the generic app icon and English-only UI text. |
| App Sandbox and entitlements | PASS (structural/local launch) | The signed entitlement dictionary exactly matches the five reviewed entitlements: sandbox, app-scoped bookmarks, user-selected read/write, audio input, and network client. No helper or extra entitlement exists. |
| Hardened Runtime | PASS | `codesign` reports `adhoc,runtime`; strict deep verification passes for both the app and archive extraction. |
| Developer ID signing | FAIL | `security find-identity -v -p codesigning` reports zero valid identities; `TeamIdentifier` is not set. |
| Notarization/stapling | FAIL | No remote submission was authorized or possible. `stapler validate` reports no ticket. |
| Gatekeeper/distribution policy | FAIL | `syspolicy_check distribution` reports an ad-hoc signature and missing notarization ticket. `spctl` rejects the bundle; there is no affirmative Gatekeeper evidence. The verifier's distribution mode also rejects the ad-hoc identity before those checks. |
| Manual update integrity | PASS (internal artifact only) | The coherent release set binds source inventory, build facts, app, ZIP, and SHA-256; the ZIP is extracted and reverified. A public update path still fails until Developer ID, notarization, clean-machine install, rollback, and publication authorization pass. |
| Automatic updater | N/A | Explicitly unapproved; no Sparkle or updater implementation/dependency exists. |
| Runtime launch/idle network | PASS (bounded host check) | The final packaged executable launched from the final bundle, opened no meeting workspace/content file, held no network socket while idle, and terminated cleanly. This is not a full packet capture of every workflow. |
| No-outbound and telemetry | PASS (contracts/static/idle) | Policy matrices, default-off content-free telemetry, log redaction/rotation, the single exact-host URLSession implementation, and the idle socket check pass. No organization telemetry destination exists. |
| Keychain/secrets | PASS | Opaque Keychain round-trip tests pass; tracked secret containers and bounded credential/private-key source patterns are absent. |
| Storage/export/retention/deletion | PASS (automated) | Permission, confined-path, managed storage, export authorization, Trash/restore/purge, recovery, and content-free logging tests pass. |
| Dependency/license review | PASS | GRDB 7.11.1 remains the only exact source dependency, is confined to persistence/tests, links into the app, and ships its privacy resource and exact MIT notice. System dynamic libraries are the only runtime dynamic dependencies. |
| Automated accessibility/keyboard checks | PASS | Existing source/structure tests cover labels, hints, values, visible status, and keyboard affordances for the implemented slices. |
| Manual accessibility/visual QA | NOT TESTED | VoiceOver, Full Keyboard Access, contrast, reduced motion, text scaling, localization, and clean-machine visual review require a human release session. |
| Repository security scan | FAIL for external release | The sealed standard scan completed 134/134 work rows and reports four medium plus three low findings. Three low resource findings are mitigated in this post-scan working tree but need a follow-up scan against an accepted revision; four medium findings remain open. |

## Signing, privacy, and dependency facts

The app is sandboxed and ad-hoc signed with Hardened Runtime. The exact signed
entitlements are:

- `com.apple.security.app-sandbox`
- `com.apple.security.files.bookmarks.app-scope`
- `com.apple.security.files.user-selected.read-write`
- `com.apple.security.device.audio-input`
- `com.apple.security.network.client`

The network entitlement is retained only for the explicit, exact-host
`https://webtv.un.org` metadata route. No media download, arbitrary-host
request, credential challenge, telemetry destination, updater, listener, or
remote command route is included.

`PrivacyInfo.xcprivacy` declares no tracking, no tracking domains, and no
collected-data categories. It documents UserDefaults use for the app-scoped
workspace bookmark, file metadata use inside app/user-selected workspace
boundaries, and disk-space checks before bounded writes. GRDB's separate empty
privacy manifest remains inside `GRDB_GRDB.bundle`.

GRDB is statically linked. `otool -L` found only Apple system libraries. The
shipped GRDB license SHA-256 is
`9853f9dce81365fcc1d9b46004633354450164b8d17904e92e80c444545f7e87`;
the shipped GRDB privacy-manifest SHA-256 is
`17784da62e51f74c5859df32fe402e01e25cdf6f797a4add06e2a3ce15c911f4`.

## Residual risks and release constraints

### P0

None established in the selected internal-alpha boundary.

### P1 publication blockers

- No Developer ID identity, Team ID, notarization ticket, affirmative
  Gatekeeper result, or clean-machine install proof exists.
- The Task 011 source is committed locally, but the generated archive was
  built before acceptance from the dirty source inventory and remains
  local/ignored; it is not a clean accepted-revision distribution build.
- Manual accessibility, localization, icon, and live TCC/capture validation are
  incomplete.

### P2 product/security limitations

- Analysis claims can become active without application-owned semantic
  entailment or human confirmation.
- Briefing text can become active based on valid source keys without generic
  semantic grounding.
- Provider-only `nonSubstantive` and `noSpeech` results can close published
  coverage without independent confirmation.
- The app is English-only and has no approved app icon.
- The initial scope is Apple Silicon only; a universal build was not selected
  or tested.
- Application-level workspace encryption remains intentionally absent under
  ADR-0012; this host has FileVault enabled, but host state is not a product
  guarantee.
- The twenty pre-existing dirty governance/architecture/ADR documents were
  deliberately preserved. `CURRENT_ARCHITECTURE.md`,
  `IMPLEMENTATION_PLAN.md`, and `MVP_ACCEPTANCE.md` still contain pre-Task-011
  status or 236-test text. `CODEX_EXECUTION_STATE.md` and this report are the
  current Task 011 authorities until those user-owned edits are reconciled
  under separate authorization.
- Current-version application reopen is proven for a cold copied workspace;
  an actual older application binary rollback and clean-machine restore are
  not tested.
- Release-set replacement is a recoverable two-rename operation, not a strict
  atomic exchange. An interrupted replacement may require inspection of the
  fail-closed `.previous-*` directory before rerunning packaging.
- The cold-backup verifier takes no OS-level workspace lock. It compares
  initial and final inventories to detect concurrent mutation, but the app
  must remain quit throughout copying and verification.
- Verification commands, results, timings, and hashes are preserved in a
  compact evidence report and release manifest, but full raw test transcripts
  are not committed.

## Publication boundary

Task 011 implementation and acceptance were committed locally. No tag, push,
notarization submission, upload, installation, or distribution occurred. The
only permissible use of the current bundle is local internal-alpha evaluation
with synthetic or non-sensitive data and human review of all derived
intelligence. External beta or release-candidate classification requires, at
minimum:

1. application-owned grounding/quarantine for all four medium findings;
2. a follow-up security scan against an accepted source revision;
3. an approved icon/localization and manual accessibility pass;
4. live TCC/capture interruption testing on the intended OS range;
5. Developer ID signing, notarization/stapling, Gatekeeper, clean-machine
   install/update/rollback evidence; and
6. separate user authorization for every commit or publication action.

## Rollback anchor

Before Task 011 the repository was at
`2a0d7fe7ac8ab10d125f3c65b6606238e4df9343`. The twenty pre-existing dirty
governance/architecture/ADR documents were preserved. Reverting Task 011 means
removing only the Task 011 code/tests/configuration/scripts/dedicated reports
listed in the completion report; no destructive Git cleanup is authorized.
User-data rollback must follow `RELEASE_BACKUP_AND_ROLLBACK.md` and must never
open a schema-v10 live workspace in an older binary without a verified
pre-upgrade copy.

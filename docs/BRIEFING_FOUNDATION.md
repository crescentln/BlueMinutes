# Task 006B Briefing Foundation

Status: Accepted
Owner: Codex under the user's Task 006B authorization
Last updated: 2026-07-18
Purpose: Record the exact first local recorded-meeting briefing slice, its
proof, and its limits without claiming Task 007 or release completion.

## Implemented vertical slice

The accepted Task 005A/005B/006A path now continues through:

```text
current full-coverage reviewed transcript
  -> current evidence-linked analysis ledger
  -> MeetingTemplate.v1
  -> IssuePositionGraph.v1 sparse issue/delegation matrix
  -> three independently generated BriefingSection.v1 revisions
  -> zero-source-text-overlap briefing coverage ledger
  -> deterministic ValidationReport.v1
  -> deterministic FinalBriefing.v1 Markdown
  -> explicit classification-checked local export
```

The Task 006B end-to-end fixture uses a private disposable workspace, a
managed synthetic canonical source, a user-confirmed complete manual
transcript, the deterministic Task 006A analysis provider, and the deterministic
Task 006B section provider. The accepted Task 005A tests separately cover real
MOV, MP4, M4A, MP3, and WAV intake and native canonicalization. No real meeting
content or user workspace is used by Task 006B tests.

The native app exposes the same repository and Task Manager route: Briefing is
a separate review destination with route disclosure, explicit local generation,
coverage/validation proof, per-section edit/lock/regeneration, Markdown preview,
and explicit local export.

## Frozen v1 contract and module set

- Semantic objects: `MeetingTemplate.v1`, `IssuePositionGraph.v1`,
  `BriefingSection.v1`, `ValidationReport.v1`, and `FinalBriefing.v1`.
- Operational records: briefing coverage ledger schema 1 and export record
  schema 1.
- Built-in template: `multilateral-diplomatic-meeting-v1`; input compatibility
  is exactly schema `1.0`; template revision
  `bf8c62a3-2ea4-52b9-866f-88cf845d7262`.
- Sections: `meeting_overview`, `major_issues`, and `major_delegations`, in that
  order. Each has an independent request, prompt module, schema, byte bound,
  provider call, revision, lock, and regeneration transaction.
- Prompt modules: the applicable overview/issues/delegations generator `1.0.0`
  plus `diplomatic-safety-rules@1.0.0`.
- Deterministic validator and renderer:
  `deterministic-briefing-validator@1.0.0` and
  `deterministic-markdown-renderer@1.0.0`.
- Production adapter: Apple Foundation Models
  `meetingbuddy-task006b-v1`, local device only, fresh no-tool guided session,
  greedy generation. Provider input categories are exactly validated
  intelligence claims and evidence identifiers; raw transcript and audio are
  excluded.

## Coverage, validation, and revision behavior

The briefing ledger consumes the exact published Task 006A analysis ledger and
its Task 005B transcript manifest. Its declared overlap policy is
`zero_source_text_overlap.v1`, the overlap count must be zero, and each eligible
segment has one normalized record linking its analysis outputs and evidence to
matrix/section item IDs. Every material conclusion must occur in the ledger;
each segment may fan out to at most four conclusion items. Missing, duplicated,
failed, untraceable, or over-fan-out coverage blocks publication.

Ten deterministic validation categories are required and blocking: template
compatibility, schema, evidence, entity resolution, source coverage, length,
provenance, contradiction, current inputs, and classification. Additional
protected rules prohibit unsupported historical-change and group-alignment
claims and require exact Position reservations and conditions. No independent
reviewing provider is authorized; deterministic validation plus manual review
is the approved boundary.

A generated section may be regenerated independently only while its exact
revision remains current, generated, and unlocked. Manual text or a lock creates
a new immutable user revision and atomically replaces the section, validation
report, final briefing, and coverage-ledger pointers. Other section and graph
revisions remain unchanged. Upstream Position changes—including repeated user
corrections—produce a new exact-input-bound graph revision, mark existing
briefing dependents stale, preserve history, and block regeneration/export of
the stale final.

## Deterministic fixture evidence

The final fixture state includes one independently regenerated section and one
manually edited, locked section. Its project-authored transcript and speaker
identities are fixed fixture inputs. Repeating the complete fixture in separate
processes, and repeating assembly with the same exact inputs, produces
identical coverage, validation, final object, and Markdown. These hashes are
also frozen as Golden test assertions:

| Artifact | SHA-256 semantic/content hash |
| --- | --- |
| Template | `17a42f2fac8f3cb7685f2d4be211131e91768971ff42cf899d25e06ee68e3883` |
| Issue-position graph | `f6c716e181ed97a59255d386bc2ad94606e97960dc7a20e67b58d78514527773` |
| Meeting overview section | `727f22bc3ee915dcf5551216ba47ece6668e2235f8f61c6e2df91eaf0deed7e9` |
| Major issues section | `2da27c7031f978499fd4935a3565eadb61bde273177aa9bcd26949bc20da6fab` |
| Major delegations section | `4c69cf4a41e243d5bc3403453a1120a576cbeb15d9465887688f9bd3b2d6c51e` |
| Briefing coverage ledger | `230f98cf14ff45cefba8589cfc0bd356eb7dc9d37e5c7431d2861d8f74f3bd21` |
| Validation report | `295e50e59448ec08fff023838585051a2504b86b387c69da19ac7b067e36f144` |
| Final briefing | `80d21fcd8a03db1c0254179e328d0da323b3338e7b65c1503b5ea830863c2ee7` |
| Exported Markdown bytes | `5790be82852fd5b77fb061c541c7f913647cc3d55ae96b470824a42d92b4db1d` |

The fixture accounts for its complete eligible segment set with zero source-
text overlap and four exact matrix/section conclusion links. Its Markdown
evidence appendix retains exact Evidence revision IDs, source-object revision
IDs, and transcript millisecond ranges. The exported bytes equal the current
`FinalBriefing.v1` Markdown exactly; a same-request retry is idempotent.

## Persistence, export, and rollback

SQLite schema version 5 (`005_briefing_foundation`) expands the closed semantic
type vocabulary and adds immutable normalized briefing ledgers, segment/
evidence/analysis-output/conclusion indexes, active pointer/events, and export
records. Fresh and accepted v1/v2/v3/v4 paths migrate forward. The v4 canary
test proves analysis-era semantic rows remain byte-identical, and the verified
pre-migration backup restores schema v4 without briefing tables. Recovery
snapshots include all five new semantic types.

Export requires an explicit user action, the exact active current valid final,
an exact expected classification, and a bounded safe filename. It writes only
to `Meetings/<meeting-id>/exports/<name>.md`, rejects traversal, symlinks,
different existing bytes, stale content, classification mismatch, and missing
authorization, uses a `0600` temporary file plus atomic rename, and records the
exact final revision, byte hash, size, classification, and authorization. It
does not upload or transmit content.

The pre-task rollback anchor is local `main` commit
`742bb8415e99f52201568dbd97014c53bee3a764`. Before acceptance/commit, rollback
means discarding only the reviewed Task 006B source/test additions and restoring
the verified schema-v4 backup for any disposable migrated workspace. Existing
Task 006A objects, user-edited/locked revisions, and evidence history must never
be deleted or silently replaced.

## Exact Task 006B and preserved-drift inventory

Task 006B added or modified these implementation, test, and task-state files:

- `Sources/MeetingBuddyDomain/StableID.swift`
- `Sources/MeetingBuddyDomain/StableStringValues.swift`
- `Sources/MeetingBuddyDomain/BriefingValues.swift`
- `Sources/MeetingBuddyDomain/MeetingTemplateV1.swift`
- `Sources/MeetingBuddyDomain/IssuePositionGraphV1.swift`
- `Sources/MeetingBuddyDomain/BriefingV1.swift`
- `Sources/MeetingBuddyApplication/AIProviderContracts.swift`
- `Sources/MeetingBuddyApplication/MediaReviewWorkflow.swift`
- `Sources/MeetingBuddyApplication/BriefingCoverageContracts.swift`
- `Sources/MeetingBuddyApplication/BriefingExportContracts.swift`
- `Sources/MeetingBuddyAI/AppleOnDeviceProviders.swift`
- `Sources/MeetingBuddyAI/TranscriptSemanticFactory.swift`
- `Sources/MeetingBuddyAI/DiplomaticBriefingPrompt.swift`
- `Sources/MeetingBuddyAI/BriefingSemanticFactory.swift`
- `Sources/MeetingBuddyAI/BriefingAssemblyFactory.swift`
- `Sources/MeetingBuddyAI/BriefingPipelineJob.swift`
- `Sources/MeetingBuddyAI/BriefingPipelineJobExecutor.swift`
- `Sources/MeetingBuddyAI/BriefingManualReviewService.swift`
- `Sources/MeetingBuddyPersistence/SQLiteSchema.swift`
- `Sources/MeetingBuddyPersistence/SQLitePersistenceStore.swift`
- `Sources/MeetingBuddyPersistence/SQLiteReferenceCodec.swift`
- `Sources/MeetingBuddyPersistence/SQLiteRecoveryService.swift`
- `Sources/MeetingBuddyPersistence/LocalMarkdownExportService.swift`
- `Sources/MeetingBuddyApp/AppMediaReviewWorkflow.swift`
- `Sources/MeetingBuddyFeatures/Models/MediaReviewModels.swift`
- `Sources/MeetingBuddyFeatures/Stores/MediaReviewStore.swift`
- `Sources/MeetingBuddyFeatures/Views/MeetingBuddyRootView.swift`
- `Sources/MeetingBuddyFeatures/Views/BriefingReviewView.swift`
- `Tests/MeetingBuddyDomainTests/BriefingContractTests.swift`
- `Tests/MeetingBuddyAITests/AnalysisPipelineIntegrationTests.swift`
- `Tests/MeetingBuddyAITests/BriefingPipelineIntegrationTests.swift`
- `Tests/MeetingBuddyAITests/AppleProviderLiveTests.swift`
- `Tests/MeetingBuddyPersistenceTests/WorkspaceAndMigrationTests.swift`
- `Tests/MeetingBuddyFeaturesTests/MediaReviewModelTests.swift`
- `docs/CODEX_EXECUTION_STATE.md`
- `docs/BRIEFING_FOUNDATION.md`
- `docs/adr/ADR-0011-task-006b-local-briefing-route.md`

The following 20 governance, roadmap, architecture, and ADR files were already
modified before Task 006B began. Their user-owned changes remain present; Task
006B reconciled applicable current-state text in place without cleaning or
replacing the pre-existing work:

- `AGENTS.md`
- `MeetingBuddy_Codex_Master_Spec_v1.0.md`
- `MeetingBuddy_Codex_Stepwise_Controller_Prompt_v1.0.md`
- `START_HERE.txt`
- `docs/CURRENT_ARCHITECTURE.md`
- `docs/DOMAIN_CONTRACTS.md`
- `docs/IMPLEMENTATION_PLAN.md`
- `docs/MVP_ACCEPTANCE.md`
- `docs/SECURITY_PRIVACY.md`
- `docs/STORAGE_POLICY.md`
- `docs/TARGET_ARCHITECTURE.md`
- `docs/adr/ADR-0002-distribution-and-sandbox.md`
- `docs/adr/ADR-0003-persistence-and-recovery.md`
- `docs/adr/ADR-0004-immutable-revisions.md`
- `docs/adr/ADR-0005-dependency-invalidation.md`
- `docs/adr/ADR-0006-provider-and-agent-boundaries.md`
- `docs/adr/ADR-0007-data-classification-and-cloud-routing.md`
- `docs/adr/ADR-0008-media-and-external-processes.md`
- `docs/adr/ADR-0010-task-006a-local-analysis-route.md`
- `docs/adr/README.md`

## Known limitations

- The built-in catalog contains only one multilateral diplomatic template and
  exactly three sections. The broader template catalog is deferred.
- Apple guided prose can vary with the OS model. Only output that passes the
  exact source-key, qualification, coverage, schema, and deterministic assembly
  gates can publish; the deterministic provider remains test-only.
- Contradiction checking is conservative deterministic validation over exact
  Position polarity, qualifications, and prohibited phrases. It is not an
  independent truth-review model, and no separate reviewing provider is
  authorized.
- An upstream correction marks the current briefing stale and blocks export.
  Task 006B does not expose a full stale-briefing refresh command; rebuilding
  that chain is deferred to reliability/workflow hardening.
- Full historical comparison remains Task 010. Group membership, silence, and
  wording variation cannot establish alignment or historical position change.
- UI visual/accessibility polish, stress/performance/long-meeting hardening,
  application-level encryption decision, retention/deletion UX, and dedicated
  no-outbound/telemetry proof remain Task 007.
- Developer ID signing, notarization, update-path review, clean-machine release
  validation, and any production-release claim remain Task 011.

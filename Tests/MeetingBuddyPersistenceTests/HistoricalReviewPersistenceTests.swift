import Foundation
import GRDB
import MeetingBuddyApplication
import MeetingBuddyDomain
import Testing
@testable import MeetingBuddyPersistence

@Suite(.serialized)
struct HistoricalReviewPersistenceTests {
    @Test
    func learnedPreferencesCoverClosedTypesAndResetRemovesEveryEffectiveValue() throws {
        let workspace = try DisposableMeetingBuddyWorkspace(suffix: "historical-preferences")
        defer { workspace.cleanup() }
        let store = try workspace.makeStore()
        defer { try? store.close() }

        let initial = try store.learnedPreferenceState(maximumEvents: 100)
        #expect(initial.globallyEnabled)
        #expect(initial.preferences.isEmpty)

        let values: [LearnedPreferenceValue] = [
            .actorCountryOrder(["Example", "Other"]),
            .briefingLength(1_200),
            .sectionOrder([.meetingOverview, .majorIssues]),
            .quotationPolicy(.exactWithTranslation),
            .grouping(.byIssue),
            .terminology([
                try TerminologyPreference(sourceTerm: "programme", displayTerm: "program")
            ]),
            .frequentTemplates([HistoricalFixture.id(990, BriefingTemplateID.self)])
        ]
        var records: [LearnedPreferenceRecord] = []
        for (index, value) in values.enumerated() {
            records.append(
                try store.saveLearnedPreference(
                    preferenceID: HistoricalFixture.id(800 + index, LearnedPreferenceID.self),
                    value: value,
                    enabled: true,
                    sourceAction: "explicit-test-action-\(index)",
                    expectedVersion: nil,
                    changedAt: HistoricalFixture.instant(10 + index)
                )
            )
        }
        #expect(Set(records.map(\.kind)) == Set(LearnedPreferenceKind.allCases))

        records[1] = try store.saveLearnedPreference(
            preferenceID: records[1].preferenceID,
            value: .briefingLength(1_500),
            enabled: true,
            sourceAction: "explicit-edit",
            expectedVersion: records[1].version,
            changedAt: HistoricalFixture.instant(29)
        )
        #expect(records[1].version == 2)
        #expect(records[1].value == .briefingLength(1_500))
        #expect(throws: HistoricalReviewError.self) {
            _ = try store.saveLearnedPreference(
                preferenceID: records[1].preferenceID,
                value: .grouping(.byActor),
                enabled: true,
                sourceAction: "explicit-invalid-type-change",
                expectedVersion: records[1].version,
                changedAt: HistoricalFixture.instant(29)
            )
        }

        let disabled = try store.setLearnedPreferenceEnabled(
            preferenceID: records[0].preferenceID,
            enabled: false,
            sourceAction: "explicit-disable",
            expectedVersion: records[0].version,
            changedAt: HistoricalFixture.instant(30)
        )
        #expect(!disabled.enabled)
        #expect(disabled.version == 2)

        try store.removeLearnedPreference(
            preferenceID: records[6].preferenceID,
            sourceAction: "explicit-remove",
            expectedVersion: records[6].version,
            changedAt: HistoricalFixture.instant(30)
        )
        #expect(
            try store.learnedPreferenceState(maximumEvents: 100)
                .preferences.contains(where: { $0.preferenceID == records[6].preferenceID }) == false
        )

        let beforeGlobalDisable = try store.learnedPreferenceState(maximumEvents: 100)
        #expect(beforeGlobalDisable.settingsVersion > initial.settingsVersion)
        #expect(throws: HistoricalReviewError.self) {
            _ = try store.resetLearnedPreferences(
                sourceAction: "stale-reset-attempt",
                expectedSettingsVersion: initial.settingsVersion,
                changedAt: HistoricalFixture.instant(31)
            )
        }
        #expect(try store.learnedPreferenceState(maximumEvents: 100).preferences.count == 6)
        let globallyDisabled = try store.setLearnedPreferencesGloballyEnabled(
            false,
            sourceAction: "explicit-global-disable",
            expectedVersion: beforeGlobalDisable.settingsVersion,
            changedAt: HistoricalFixture.instant(31)
        )
        #expect(!globallyDisabled.globallyEnabled)
        #expect(globallyDisabled.preferences.count == 6)

        let reset = try store.resetLearnedPreferences(
            sourceAction: "explicit-reset-all",
            expectedSettingsVersion: globallyDisabled.settingsVersion,
            changedAt: HistoricalFixture.instant(32)
        )
        #expect(reset.globallyEnabled)
        #expect(reset.preferences.isEmpty)
        #expect(reset.recentEvents.first?.action == .resetAll)

        let databaseFacts = try store.databasePool.read { db in
            (
                preferenceRows: try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM learned_preferences"
                ),
                eventPayloadColumns: try Row.fetchAll(
                    db,
                    sql: "PRAGMA table_info(learned_preference_events)"
                ).compactMap { $0["name"] as String? }.filter {
                    $0.contains("payload") || $0.contains("value_blob")
                },
                resetEvents: try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM learned_preference_events WHERE action = 'reset_all'"
                ),
                removalEvents: try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM learned_preference_events WHERE action = 'removed'"
                )
            )
        }
        #expect(databaseFacts.preferenceRows == 0)
        #expect(databaseFacts.eventPayloadColumns.isEmpty)
        #expect(databaseFacts.resetEvents == 1)
        #expect(databaseFacts.removalEvents == 1)
    }

    @Test
    func rebuildSearchAndComparisonAreDeterministicEvidenceLinkedAndConservative() throws {
        let workspace = try DisposableMeetingBuddyWorkspace(suffix: "historical-search")
        defer { workspace.cleanup() }
        let store = try workspace.makeStore()
        defer { try? store.close() }

        _ = try HistoricalFixture.insertHistory(
            in: store,
            workspaceID: workspace.descriptor.manifest.workspaceID,
            base: 100,
            date: CalendarDate(year: 2025, month: 6, day: 1),
            positionType: .supports,
            statement: "We support the verified proposal."
        )
        _ = try HistoricalFixture.insertHistory(
            in: store,
            workspaceID: workspace.descriptor.manifest.workspaceID,
            base: 200,
            date: CalendarDate(year: 2026, month: 6, day: 1),
            positionType: .supports,
            statement: "The verified proposal has our support."
        )

        #expect(try store.historicalIndexStatus().availability == .rebuildRequired)
        let firstRebuild = try store.rebuildHistoricalIndex(
            at: HistoricalFixture.instant(40),
            cancellationCheck: {}
        )
        #expect(firstRebuild.indexedPositionCount == 2)
        #expect(firstRebuild.skippedUnsafePositionCount == 0)

        let query = try HistoricalSearchQuery(
            actorOrCountry: "EX",
            topic: "Verified topic",
            meetingBody: "Synthetic body",
            startDate: CalendarDate(year: 2025, month: 1, day: 1),
            endDate: CalendarDate(year: 2026, month: 12, day: 31),
            pageSize: 10
        )
        let firstPage = try store.searchHistory(query)
        let secondPage = try store.searchHistory(query)
        #expect(firstPage.results.map(\.id) == secondPage.results.map(\.id))
        #expect(firstPage.results.count == 2)
        #expect(firstPage.results[0].meeting.meetingDate == (try CalendarDate(year: 2026, month: 6, day: 1)))
        #expect(firstPage.results.allSatisfy { $0.evidence.count == 1 })
        let organizationAndIssue = try store.searchHistory(
            HistoricalSearchQuery(
                organization: "Synthetic body",
                issue: "Verified topic",
                pageSize: 10
            )
        )
        #expect(organizationAndIssue.results.map(\.id) == firstPage.results.map(\.id))
        #expect(
            try store.searchHistory(
                HistoricalSearchQuery(
                    meetingType: MeetingTemplateType.multilateralDiplomaticMeeting.encodedValue,
                    pageSize: 10
                )
            ).results.isEmpty
        )
        let firstCursorPage = try store.searchHistory(
            HistoricalSearchQuery(actorOrCountry: "EX", pageSize: 1)
        )
        let cursor = try #require(firstCursorPage.nextCursor)
        let nextCursorPage = try store.searchHistory(
            HistoricalSearchQuery(actorOrCountry: "EX", cursor: cursor, pageSize: 1)
        )
        #expect(firstCursorPage.results.count == 1)
        #expect(nextCursorPage.results.count == 1)
        #expect(firstCursorPage.results[0].id != nextCursorPage.results[0].id)

        let wordingOnly = HistoricalComparisonEvaluator.evaluate(
            current: firstPage.results[0],
            historical: firstPage.results[1]
        )
        #expect(wordingOnly.differenceState == .noConfirmedDifference)
        #expect(wordingOnly.finding == .wordingOnlyDifference)
        #expect(wordingOnly.qualifiedSummary.contains("policy change is not established"))
        let reversedEffectiveTime = HistoricalComparisonEvaluator.evaluate(
            current: firstPage.results[1],
            historical: firstPage.results[0]
        )
        #expect(reversedEffectiveTime.differenceState == .insufficientEvidence)
        #expect(reversedEffectiveTime.finding == .insufficientEvidence)

        let candidate = try HistoricalComparisonFactory.candidate(
            evaluation: wordingOnly,
            comparisonID: HistoricalFixture.id(500, HistoricalComparisonID.self),
            revisionID: HistoricalFixture.id(501, RevisionID.self),
            createdAt: HistoricalFixture.instant(41)
        )
        #expect(candidate.currentEvidenceRevisions.count == 1)
        #expect(candidate.historicalEvidenceRevisions.count == 1)
        #expect(candidate.currentAccessPolicyRevision.objectType == .accessPolicy)
        #expect(throws: HistoricalReviewError.self) {
            _ = try HistoricalComparisonFactory.confirmedChange(
                candidate: candidate,
                revisionID: HistoricalFixture.id(502, RevisionID.self),
                confirmedAt: HistoricalFixture.instant(42)
            )
        }

        let secondRebuild = try store.rebuildHistoricalIndex(
            at: HistoricalFixture.instant(43),
            cancellationCheck: {}
        )
        let rebuiltPage = try store.searchHistory(query)
        #expect(secondRebuild.sourceFingerprint == firstRebuild.sourceFingerprint)
        #expect(rebuiltPage.results.map(\.id) == firstPage.results.map(\.id))
        #expect(throws: HistoricalReviewError.self) {
            _ = try store.searchHistory(
                HistoricalSearchQuery(actorOrCountry: "EX", cursor: cursor, pageSize: 1)
            )
        }
    }

    @Test
    func structuralDifferenceRequiresAndPersistsAUserConfirmedSupersedingRevision() throws {
        let workspace = try DisposableMeetingBuddyWorkspace(suffix: "historical-confirmation")
        defer { workspace.cleanup() }
        let store = try workspace.makeStore()
        defer { try? store.close() }

        let historical = try HistoricalFixture.insertHistory(
            in: store,
            workspaceID: workspace.descriptor.manifest.workspaceID,
            base: 400,
            date: CalendarDate(year: 2025, month: 2, day: 1),
            positionType: .supports,
            statement: "We support the verified proposal.",
            effectiveTimeRange: MediaTimeRange(
                startMilliseconds: 1_000,
                endMilliseconds: 2_000
            )
        )
        let current = try HistoricalFixture.insertHistory(
            in: store,
            workspaceID: workspace.descriptor.manifest.workspaceID,
            base: 500,
            date: CalendarDate(year: 2026, month: 2, day: 1),
            positionType: .opposes,
            statement: "We oppose the verified proposal.",
            effectiveTimeRange: MediaTimeRange(
                startMilliseconds: 3_000,
                endMilliseconds: 4_000
            )
        )
        _ = try store.rebuildHistoricalIndex(
            at: HistoricalFixture.instant(60),
            cancellationCheck: {}
        )
        let results = try store.searchHistory(
            HistoricalSearchQuery(actorOrCountry: "EX", topic: "verified topic")
        ).results
        let evaluation = HistoricalComparisonEvaluator.evaluate(
            current: try #require(results.first(where: {
                $0.position.revision.revisionID == current.position.revision.revisionID
            })),
            historical: try #require(results.first(where: {
                $0.position.revision.revisionID == historical.position.revision.revisionID
            }))
        )
        #expect(evaluation.differenceState == .possibleDifference)
        #expect(evaluation.finding == .possibleChange)

        let candidate = try HistoricalComparisonFactory.candidate(
            evaluation: evaluation,
            comparisonID: HistoricalFixture.id(600, HistoricalComparisonID.self),
            revisionID: HistoricalFixture.id(601, RevisionID.self),
            createdAt: HistoricalFixture.instant(61)
        )
        #expect(candidate.revision.createdBy == .application)
        #expect(!candidate.userConfirmed)
        #expect(candidate.historicalEffectiveTimeRange == historical.position.effectiveTimeRange)
        #expect(candidate.currentEffectiveTimeRange == current.position.effectiveTimeRange)
        try store.databasePool.write { db in
            try db.execute(
                sql: "DELETE FROM active_published_revisions WHERE object_type = 'access_policy' AND logical_id = ?",
                arguments: [current.policy.policyID.canonicalString]
            )
        }
        #expect(throws: HistoricalReviewError.accessDenied) {
            try store.publishHistoricalComparison(
                candidate,
                expectedCurrentRevisionID: nil,
                changedAt: HistoricalFixture.instant(61)
            )
        }
        _ = try store.activate(
            ActivePublishedRevisionSelection(
                logicalID: current.policy.policyID,
                revisionID: current.policy.revision.revisionID
            ),
            as: AccessPolicyV1.self,
            expectedCurrentRevisionID: nil,
            markedAt: HistoricalFixture.instant(61)
        )
        try store.publishHistoricalComparison(
            candidate,
            expectedCurrentRevisionID: nil,
            changedAt: HistoricalFixture.instant(61)
        )

        let confirmed = try HistoricalComparisonFactory.confirmedChange(
            candidate: candidate,
            revisionID: HistoricalFixture.id(602, RevisionID.self),
            confirmedAt: HistoricalFixture.instant(62)
        )
        #expect(confirmed.differenceState == .userConfirmedDifference)
        #expect(confirmed.finding == .userConfirmedChange)
        #expect(confirmed.revision.createdBy == .user)
        #expect(confirmed.revision.supersedesRevisionID == candidate.revision.revisionID)
        #expect(confirmed.confirmationOfRevision?.revisionID == candidate.revision.revisionID)
        try store.publishHistoricalComparison(
            confirmed,
            expectedCurrentRevisionID: candidate.revision.revisionID,
            changedAt: HistoricalFixture.instant(62)
        )

        #expect(
            try store.fetch(
                HistoricalComparisonV1.self,
                revisionID: candidate.revision.revisionID
            ) == candidate
        )
        #expect(
            try store.fetch(
                HistoricalComparisonV1.self,
                revisionID: confirmed.revision.revisionID
            ) == confirmed
        )
        #expect(
            try store.fetch(PositionV1.self, revisionID: historical.position.revision.revisionID)
                == historical.position
        )
        #expect(
            try store.fetch(PositionV1.self, revisionID: current.position.revision.revisionID)
                == current.position
        )
        let recovery = SQLiteRecoveryService(store: store, storage: workspace.storage)
        let manifest = try recovery.createRecoverySnapshot(
            createdAt: HistoricalFixture.instant(63)
        )
        try recovery.verifyRecoverySnapshot(manifest)
        let semanticSnapshot = try String(
            contentsOf: workspace.root.appendingPathComponent(
                manifest.semanticSnapshot.relativePath.rawValue
            ),
            encoding: .utf8
        )
        #expect(semanticSnapshot.contains("\"object_type\":\"historical_comparison\""))
        #expect(semanticSnapshot.contains(confirmed.revision.revisionID.canonicalString))
    }

    @Test
    func cancelledRebuildLeavesThePriorCompleteGenerationWithoutPartialRows() throws {
        let workspace = try DisposableMeetingBuddyWorkspace(suffix: "historical-cancel")
        defer { workspace.cleanup() }
        let store = try workspace.makeStore()
        defer { try? store.close() }
        _ = try HistoricalFixture.insertHistory(
            in: store,
            workspaceID: workspace.descriptor.manifest.workspaceID,
            base: 620,
            date: CalendarDate(year: 2025, month: 4, day: 1),
            positionType: .supports,
            statement: "We support the verified proposal."
        )
        let first = try store.rebuildHistoricalIndex(
            at: HistoricalFixture.instant(63),
            cancellationCheck: {}
        )
        #expect(first.replacementGeneration == 1)
        _ = try HistoricalFixture.insertHistory(
            in: store,
            workspaceID: workspace.descriptor.manifest.workspaceID,
            base: 680,
            date: CalendarDate(year: 2026, month: 4, day: 1),
            positionType: .supports,
            statement: "We continue to support the verified proposal."
        )
        #expect(try store.historicalIndexStatus().availability == .rebuildRequired)
        #expect(throws: CancellationError.self) {
            _ = try store.rebuildHistoricalIndex(
                at: HistoricalFixture.instant(64),
                cancellationCheck: { throw CancellationError() }
            )
        }
        let facts = try store.databasePool.read { db in
            (
                stateGeneration: try Int.fetchOne(
                    db,
                    sql: "SELECT generation FROM historical_index_state WHERE singleton = 1"
                ),
                stateCurrent: try Int.fetchOne(
                    db,
                    sql: "SELECT is_current FROM historical_index_state WHERE singleton = 1"
                ),
                generations: try Int.fetchAll(
                    db,
                    sql: "SELECT DISTINCT generation FROM historical_position_index ORDER BY generation"
                ),
                rows: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM historical_position_index")
            )
        }
        #expect(facts.stateGeneration == 1)
        #expect(facts.stateCurrent == 0)
        #expect(facts.generations == [1])
        #expect(facts.rows == 1)
    }

    @Test
    func evidenceAdmissionRequiresExactIntegrityAndSeparatelyAuthorizedSourceShape() throws {
        let at = HistoricalFixture.instant(70)
        let assetID = HistoricalFixture.id(700, SourceAssetID.self)
        let revisionID = HistoricalFixture.id(701, RevisionID.self)
        let digest = try ContentDigest(
            algorithm: .sha256,
            lowercaseHex: String(repeating: "a", count: 64)
        )
        let localDraft = try SourceAssetV1(
            revision: HistoricalFixture.envelope(
                logicalID: assetID,
                revisionID: revisionID,
                createdBy: .user,
                at: at
            ),
            meetingID: HistoricalFixture.id(702, MeetingID.self),
            assetType: .document,
            originType: .localImport,
            managedStorageReference: ManagedAssetReference(
                storageObjectID: HistoricalFixture.id(703, StorageObjectID.self)
            ),
            sourceContentHash: digest,
            mimeType: MIMEType("application/pdf"),
            byteSize: 42,
            acquisitionMethod: .userSelectedFile,
            acquiredAt: at,
            retentionClass: .workspaceManaged
        )
        let exactReference = try HistoricalFixture.reference(assetID, revisionID)
        let draftDescriptor = try HistoricalEvidenceSourceDescriptor(
            kind: .versionedDocument,
            sourceAssetRevision: exactReference,
            sourceContentHash: digest,
            byteSize: 42,
            acquiredAt: at,
            remoteResourcesDisabled: true
        )
        #expect(throws: HistoricalReviewError.self) {
            try HistoricalEvidenceAdmission.validate(draftDescriptor, sourceAsset: localDraft)
        }
        let localDocument = try SourceAssetV1(
            revision: HistoricalFixture.envelope(
                logicalID: assetID,
                revisionID: revisionID,
                createdBy: .user,
                semanticHash: localDraft.calculatedSemanticContentHash(),
                published: true,
                at: at
            ),
            meetingID: localDraft.meetingID,
            assetType: localDraft.assetType,
            originType: localDraft.originType,
            sourceURL: localDraft.sourceURL,
            managedStorageReference: localDraft.managedStorageReference,
            sourceContentHash: localDraft.sourceContentHash,
            mimeType: localDraft.mimeType,
            byteSize: localDraft.byteSize,
            language: localDraft.language,
            acquisitionMethod: localDraft.acquisitionMethod,
            acquiredAt: localDraft.acquiredAt,
            retentionClass: localDraft.retentionClass,
            media: localDraft.media
        )
        for kind in [HistoricalEvidenceSourceKind.versionedDocument, .permittedEmailImport] {
            let descriptor = try HistoricalEvidenceSourceDescriptor(
                kind: kind,
                sourceAssetRevision: exactReference,
                sourceContentHash: digest,
                byteSize: 42,
                acquiredAt: at,
                remoteResourcesDisabled: true
            )
            try HistoricalEvidenceAdmission.validate(descriptor, sourceAsset: localDocument)
        }

        let wrongDigest = try ContentDigest(
            algorithm: .sha256,
            lowercaseHex: String(repeating: "b", count: 64)
        )
        let mismatched = try HistoricalEvidenceSourceDescriptor(
            kind: .versionedDocument,
            sourceAssetRevision: exactReference,
            sourceContentHash: wrongDigest,
            byteSize: 42,
            acquiredAt: at,
            remoteResourcesDisabled: true
        )
        #expect(throws: HistoricalReviewError.self) {
            try HistoricalEvidenceAdmission.validate(mismatched, sourceAsset: localDocument)
        }
        #expect(throws: HistoricalReviewError.self) {
            _ = try HistoricalEvidenceSourceDescriptor(
                kind: .permittedEmailImport,
                sourceAssetRevision: exactReference,
                sourceContentHash: digest,
                byteSize: 42,
                acquiredAt: at,
                remoteResourcesDisabled: false
            )
        }

        let publicAssetID = HistoricalFixture.id(710, SourceAssetID.self)
        let publicRevisionID = HistoricalFixture.id(711, RevisionID.self)
        let publicDraft = try SourceAssetV1(
            revision: HistoricalFixture.envelope(
                logicalID: publicAssetID,
                revisionID: publicRevisionID,
                createdBy: .application,
                at: at
            ),
            meetingID: HistoricalFixture.id(712, MeetingID.self),
            assetType: .document,
            originType: .approvedWebSource,
            sourceURL: HTTPSURL("https://example.invalid/versioned-statement.pdf"),
            managedStorageReference: ManagedAssetReference(
                storageObjectID: HistoricalFixture.id(713, StorageObjectID.self)
            ),
            sourceContentHash: digest,
            mimeType: MIMEType("application/pdf"),
            byteSize: 42,
            acquisitionMethod: .approvedHTTPSDownload,
            acquiredAt: at,
            retentionClass: .workspaceManaged
        )
        let publicDocument = try SourceAssetV1(
            revision: HistoricalFixture.envelope(
                logicalID: publicAssetID,
                revisionID: publicRevisionID,
                createdBy: .application,
                semanticHash: publicDraft.calculatedSemanticContentHash(),
                published: true,
                at: at
            ),
            meetingID: publicDraft.meetingID,
            assetType: publicDraft.assetType,
            originType: publicDraft.originType,
            sourceURL: publicDraft.sourceURL,
            managedStorageReference: publicDraft.managedStorageReference,
            sourceContentHash: publicDraft.sourceContentHash,
            mimeType: publicDraft.mimeType,
            byteSize: publicDraft.byteSize,
            language: publicDraft.language,
            acquisitionMethod: publicDraft.acquisitionMethod,
            acquiredAt: publicDraft.acquiredAt,
            retentionClass: publicDraft.retentionClass,
            media: publicDraft.media
        )
        let publicDescriptor = try HistoricalEvidenceSourceDescriptor(
            kind: .permittedPublicSource,
            sourceAssetRevision: HistoricalFixture.reference(publicAssetID, publicRevisionID),
            sourceContentHash: digest,
            byteSize: 42,
            acquiredAt: at,
            remoteResourcesDisabled: false
        )
        try HistoricalEvidenceAdmission.validate(publicDescriptor, sourceAsset: publicDocument)
    }

    @Test
    func historicalIndexAndFilteredQueryStayBoundedAtTenThousandPublishedPositions() throws {
        let workspace = try DisposableMeetingBuddyWorkspace(suffix: "historical-scale-10000")
        defer { workspace.cleanup() }
        let store = try workspace.makeStore()
        defer { try? store.close() }
        let seed = try HistoricalFixture.insertHistory(
            in: store,
            workspaceID: workspace.descriptor.manifest.workspaceID,
            base: 900,
            date: CalendarDate(year: 2026, month: 7, day: 1),
            positionType: .supports,
            statement: "We support the verified proposal."
        )
        let changedAt = HistoricalFixture.instant(95)
        try store.databasePool.write { db in
            for offset in 1..<10_000 {
                let clone = try HistoricalFixture.positionCopy(
                    seed.position,
                    positionID: HistoricalFixture.scaleID(offset, PositionID.self),
                    revisionID: HistoricalFixture.scaleID(20_000 + offset, RevisionID.self),
                    at: changedAt
                )
                try store.insertPublicationObject(clone, in: db)
                try store.initializeActivePointer(for: clone, at: changedAt, in: db)
            }
        }

        let clock = ContinuousClock()
        let rebuildStart = clock.now
        let report = try store.rebuildHistoricalIndex(
            at: HistoricalFixture.instant(96),
            cancellationCheck: {}
        )
        let rebuildDuration = rebuildStart.duration(to: clock.now)
        #expect(report.indexedPositionCount == 10_000)
        #expect(report.skippedUnsafePositionCount == 0)
        #expect(rebuildDuration < .seconds(30))

        let query = try HistoricalSearchQuery(
            actorOrCountry: "EX",
            topic: "verified topic",
            meetingBody: "synthetic body",
            reviewStatus: .confirmed,
            pageSize: 100
        )
        let searchStart = clock.now
        let first = try store.searchHistory(query)
        let searchDuration = searchStart.duration(to: clock.now)
        let repeated = try store.searchHistory(query)
        #expect(first.results.count == 100)
        #expect(first.results.map(\.id) == repeated.results.map(\.id))
        #expect(first.indexGeneration == report.replacementGeneration)
        #expect(searchDuration < .seconds(5))
        print(
            "TASK010_SCALE positions=10000 rebuild=\(rebuildDuration) "
                + "filtered_first_page=\(searchDuration)"
        )
    }

    @Test
    func policyChangeFailsClosedBeforeReturningHistoryContentOrCount() throws {
        let workspace = try DisposableMeetingBuddyWorkspace(suffix: "historical-policy")
        defer { workspace.cleanup() }
        let store = try workspace.makeStore()
        defer { try? store.close() }
        let fixture = try HistoricalFixture.insertHistory(
            in: store,
            workspaceID: workspace.descriptor.manifest.workspaceID,
            base: 300,
            date: CalendarDate(year: 2026, month: 1, day: 1),
            positionType: .opposes,
            statement: "We oppose the verified proposal."
        )
        _ = try store.rebuildHistoricalIndex(
            at: HistoricalFixture.instant(50),
            cancellationCheck: {}
        )
        let query = try HistoricalSearchQuery(pageSize: 10)
        #expect(try store.searchHistory(query).results.count == 1)
        #expect(
            try store.searchHistory(
                HistoricalSearchQuery(maximumClassification: .public, pageSize: 10)
            ).results.isEmpty
        )

        try store.setHistoricalIndexEnabled(false, changedAt: HistoricalFixture.instant(51))
        let disabledStatus = try store.historicalIndexStatus()
        #expect(disabledStatus.availability == .disabled)
        #expect(disabledStatus.indexedPositionCount == 0)
        #expect(disabledStatus.sourceFingerprint == nil)
        #expect(throws: HistoricalReviewError.indexDisabled) {
            _ = try store.searchHistory(query)
        }
        try store.setHistoricalIndexEnabled(true, changedAt: HistoricalFixture.instant(52))
        #expect(try store.searchHistory(query).results.count == 1)

        try store.databasePool.write { db in
            try db.execute(
                sql: "DELETE FROM active_published_revisions WHERE object_type = 'access_policy' AND logical_id = ?",
                arguments: [fixture.policy.policyID.canonicalString]
            )
        }
        let dirtyStatus = try store.historicalIndexStatus()
        #expect(dirtyStatus.availability == .rebuildRequired)
        #expect(dirtyStatus.indexedPositionCount == 0)
        #expect(dirtyStatus.sourceFingerprint == nil)
        try store.databasePool.write { db in
            try db.execute(
                sql: "UPDATE historical_index_state SET is_current = 1 WHERE singleton = 1"
            )
        }
        #expect(try store.searchHistory(query).results.isEmpty)
    }
}

private enum HistoricalFixture {
    struct StoredHistory {
        let meeting: MeetingProfileV1
        let position: PositionV1
        let policy: AccessPolicyV1
    }

    static func id<Tag>(_ suffix: Int, _ type: StableID<Tag>.Type) -> StableID<Tag> {
        let value = String(format: "90000000-0000-0000-0000-%012d", suffix)
        return StableID<Tag>(UUID(uuidString: value)!)
    }

    static func scaleID<Tag>(_ suffix: Int, _ type: StableID<Tag>.Type) -> StableID<Tag> {
        let value = String(format: "91000000-0000-0000-0000-%012d", suffix)
        return StableID<Tag>(UUID(uuidString: value)!)
    }

    static func instant(_ offset: Int) -> UTCInstant {
        try! UTCInstant(millisecondsSinceUnixEpoch: 1_760_000_000_000 + Int64(offset))
    }

    static func envelope<Tag: LogicalObjectIDScope>(
        logicalID: StableID<Tag>,
        revisionID: RevisionID,
        createdBy: CreationActor,
        inputs: [SemanticRevisionReference] = [],
        evidence: [SemanticRevisionReference] = [],
        semanticHash: ContentDigest? = nil,
        published: Bool = false,
        at: UTCInstant
    ) throws -> RevisionEnvelope<Tag> {
        try RevisionEnvelope(
            logicalID: logicalID,
            revisionID: revisionID,
            schemaVersion: .v1,
            lifecycleStatus: published ? .published : .draft,
            validationState: published ? .valid : .notValidated,
            createdAt: at,
            createdBy: createdBy,
            publishedAt: published ? at : nil,
            inputRevisions: inputs,
            evidenceRevisions: evidence,
            dataClassification: .internal,
            semanticContentHash: semanticHash
        )
    }

    static func reference<Tag: LogicalObjectIDScope>(
        _ logicalID: StableID<Tag>,
        _ revisionID: RevisionID
    ) throws -> SemanticRevisionReference {
        try SemanticRevisionReference(logicalID: logicalID, revisionID: revisionID)
    }

    static func insertHistory(
        in store: SQLitePersistenceStore,
        workspaceID: WorkspaceID,
        base: Int,
        date: CalendarDate,
        positionType: PositionType,
        statement: String,
        effectiveTimeRange: MediaTimeRange? = nil
    ) throws -> StoredHistory {
        let at = instant(base)
        let meetingID = id(base + 1, MeetingID.self)
        let meetingRevisionID = id(base + 2, RevisionID.self)
        let meetingDraft = try MeetingProfileV1(
            revision: envelope(
                logicalID: meetingID,
                revisionID: meetingRevisionID,
                createdBy: .user,
                at: at
            ),
            title: "Synthetic history meeting \(base)",
            meetingDate: date,
            organizationOrUNBody: .unresolved(label: "Synthetic body"),
            outputLanguage: LanguageTag("en"),
            cloudProcessingPolicy: .localOnly,
            workspaceID: workspaceID,
            reviewStatus: .confirmed,
            userConfirmed: true
        )
        let meeting = try MeetingProfileV1(
            revision: envelope(
                logicalID: meetingID,
                revisionID: meetingRevisionID,
                createdBy: .user,
                semanticHash: meetingDraft.calculatedSemanticContentHash(),
                published: true,
                at: at
            ),
            title: meetingDraft.title,
            meetingDate: date,
            organizationOrUNBody: meetingDraft.organizationOrUNBody,
            outputLanguage: meetingDraft.outputLanguage,
            cloudProcessingPolicy: .localOnly,
            workspaceID: workspaceID,
            reviewStatus: .confirmed,
            userConfirmed: true
        )
        try store.insert(meeting)
        _ = try store.activate(
            ActivePublishedRevisionSelection(
                logicalID: meeting.meetingID,
                revisionID: meeting.revision.revisionID
            ),
            as: MeetingProfileV1.self,
            expectedCurrentRevisionID: nil,
            markedAt: at
        )
        let meetingReference = try reference(meeting.meetingID, meeting.revision.revisionID)

        let security = try LocalSecurityPolicyFactory().makeDefault(
            meeting: meeting,
            sensitivityLabelID: id(base + 3, SensitivityLabelID.self),
            sensitivityLabelRevisionID: id(base + 4, RevisionID.self),
            accessPolicyID: id(base + 5, AccessPolicyID.self),
            accessPolicyRevisionID: id(base + 6, RevisionID.self),
            createdAt: at
        )
        try store.insert(security.sensitivityLabel)
        _ = try store.activate(
            ActivePublishedRevisionSelection(
                logicalID: security.sensitivityLabel.labelID,
                revisionID: security.sensitivityLabel.revision.revisionID
            ),
            as: SensitivityLabelV1.self,
            expectedCurrentRevisionID: nil,
            markedAt: at
        )
        try store.insert(security.accessPolicy)
        _ = try store.activate(
            ActivePublishedRevisionSelection(
                logicalID: security.accessPolicy.policyID,
                revisionID: security.accessPolicy.revision.revisionID
            ),
            as: AccessPolicyV1.self,
            expectedCurrentRevisionID: nil,
            markedAt: at
        )

        let evidenceID = id(base + 7, EvidenceID.self)
        let evidenceRevisionID = id(base + 8, RevisionID.self)
        let evidenceDraft = try EvidenceRefV1(
            revision: envelope(
                logicalID: evidenceID,
                revisionID: evidenceRevisionID,
                createdBy: .application,
                inputs: [meetingReference],
                at: at
            ),
            location: .meetingMetadata(source: meetingReference, field: "title"),
            excerpt: EvidenceExcerpt(
                text: statement,
                language: LanguageTag("en"),
                translationStatus: .sourceOnly
            ),
            confidence: ConfidenceScore(millionths: 950_000)
        )
        let evidence = try EvidenceRefV1(
            revision: envelope(
                logicalID: evidenceID,
                revisionID: evidenceRevisionID,
                createdBy: .application,
                inputs: [meetingReference],
                semanticHash: evidenceDraft.calculatedSemanticContentHash(),
                published: true,
                at: at
            ),
            location: evidenceDraft.location,
            excerpt: evidenceDraft.excerpt,
            confidence: evidenceDraft.confidence
        )
        try store.insert(evidence)
        _ = try store.activate(
            ActivePublishedRevisionSelection(
                logicalID: evidence.evidenceID,
                revisionID: evidence.revision.revisionID
            ),
            as: EvidenceRefV1.self,
            expectedCurrentRevisionID: nil,
            markedAt: at
        )
        let evidenceReference = try reference(evidence.evidenceID, evidence.revision.revisionID)

        let actorID = id(base + 9, ActorID.self)
        let actorRevisionID = id(base + 10, RevisionID.self)
        let actorDraft = try ActorV1(
            revision: envelope(
                logicalID: actorID,
                revisionID: actorRevisionID,
                createdBy: .user,
                at: at
            ),
            identity: .country(displayName: "State of Example", countryCode: CountryCode("EX")),
            canonicalAliases: ["Example"],
            reviewStatus: .confirmed,
            userConfirmed: true
        )
        let actor = try ActorV1(
            revision: envelope(
                logicalID: actorID,
                revisionID: actorRevisionID,
                createdBy: .user,
                semanticHash: actorDraft.calculatedSemanticContentHash(),
                published: true,
                at: at
            ),
            identity: actorDraft.identity,
            canonicalAliases: actorDraft.canonicalAliases,
            reviewStatus: .confirmed,
            userConfirmed: true
        )
        try store.insert(actor)
        _ = try store.activate(
            ActivePublishedRevisionSelection(
                logicalID: actor.actorID,
                revisionID: actor.revision.revisionID
            ),
            as: ActorV1.self,
            expectedCurrentRevisionID: nil,
            markedAt: at
        )

        let claim = try EvidenceLinkedClaim(
            text: "Verified topic",
            taxonomy: .sourceFact,
            supportStatus: .supported,
            evidenceRevisions: [evidenceReference],
            confidence: ConfidenceScore(millionths: 950_000)
        )
        let issueID = id(base + 11, IssueID.self)
        let issueRevisionID = id(base + 12, RevisionID.self)
        let issueInputs = [meetingReference]
        let issueDraft = try IssueV1(
            revision: envelope(
                logicalID: issueID,
                revisionID: issueRevisionID,
                createdBy: .user,
                inputs: issueInputs,
                evidence: [evidenceReference],
                at: at
            ),
            meetingID: meetingID,
            title: claim,
            reviewStatus: .confirmed,
            userConfirmed: true
        )
        let issue = try IssueV1(
            revision: envelope(
                logicalID: issueID,
                revisionID: issueRevisionID,
                createdBy: .user,
                inputs: issueInputs,
                evidence: [evidenceReference],
                semanticHash: issueDraft.calculatedSemanticContentHash(),
                published: true,
                at: at
            ),
            meetingID: meetingID,
            title: claim,
            reviewStatus: .confirmed,
            userConfirmed: true
        )
        try store.insert(issue)
        _ = try store.activate(
            ActivePublishedRevisionSelection(
                logicalID: issue.issueID,
                revisionID: issue.revision.revisionID
            ),
            as: IssueV1.self,
            expectedCurrentRevisionID: nil,
            markedAt: at
        )

        let actorReference = try reference(actor.actorID, actor.revision.revisionID)
        let issueReference = try reference(issue.issueID, issue.revision.revisionID)
        let organizationID = id(base + 13, OrganizationID.self)
        let organizationRevisionID = id(base + 14, RevisionID.self)
        let organizationDraft = try OrganizationV1(
            revision: envelope(
                logicalID: organizationID,
                revisionID: organizationRevisionID,
                createdBy: .user,
                inputs: [actorReference],
                evidence: [evidenceReference],
                at: at
            ),
            actorRevision: actorReference,
            kind: .country,
            displayName: actor.displayName,
            countryCode: CountryCode("EX"),
            confidence: ConfidenceScore(millionths: 950_000),
            reviewStatus: .confirmed,
            userConfirmed: true
        )
        let organization = try OrganizationV1(
            revision: envelope(
                logicalID: organizationID,
                revisionID: organizationRevisionID,
                createdBy: .user,
                inputs: [actorReference],
                evidence: [evidenceReference],
                semanticHash: organizationDraft.calculatedSemanticContentHash(),
                published: true,
                at: at
            ),
            actorRevision: actorReference,
            kind: .country,
            displayName: actor.displayName,
            countryCode: CountryCode("EX"),
            confidence: ConfidenceScore(millionths: 950_000),
            reviewStatus: .confirmed,
            userConfirmed: true
        )
        try store.insert(organization)
        let organizationReference = try reference(
            organization.organizationID, organization.revision.revisionID
        )

        let capacityID = id(base + 15, SpeakingCapacityID.self)
        let capacityRevisionID = id(base + 16, RevisionID.self)
        let capacityInputs = [meetingReference, actorReference]
        let relationship = try RepresentationRelationship(
            kind: .represents,
            entityRevision: actorReference
        )
        let capacityDraft = try SpeakingCapacityV1(
            revision: envelope(
                logicalID: capacityID,
                revisionID: capacityRevisionID,
                createdBy: .user,
                inputs: capacityInputs,
                evidence: [evidenceReference],
                at: at
            ),
            meetingID: meetingID,
            speakerActorRevision: actorReference,
            representationRelationships: [relationship],
            meetingRole: .delegate,
            reviewStatus: .confirmed,
            userConfirmed: true
        )
        let capacity = try SpeakingCapacityV1(
            revision: envelope(
                logicalID: capacityID,
                revisionID: capacityRevisionID,
                createdBy: .user,
                inputs: capacityInputs,
                evidence: [evidenceReference],
                semanticHash: capacityDraft.calculatedSemanticContentHash(),
                published: true,
                at: at
            ),
            meetingID: meetingID,
            speakerActorRevision: actorReference,
            representationRelationships: [relationship],
            meetingRole: .delegate,
            reviewStatus: .confirmed,
            userConfirmed: true
        )
        try store.insert(capacity)
        let capacityReference = try reference(capacity.capacityID, capacity.revision.revisionID)
        let positionID = id(base + 17, PositionID.self)
        let positionRevisionID = id(base + 18, RevisionID.self)
        let positionInputs = [
            meetingReference, actorReference, organizationReference,
            capacityReference, issueReference
        ]
        let statementClaim = try EvidenceLinkedClaim(
            text: statement,
            taxonomy: .delegationClaim,
            supportStatus: .supported,
            evidenceRevisions: [evidenceReference],
            confidence: ConfidenceScore(millionths: 900_000)
        )
        let positionDraft = try PositionV1(
            revision: envelope(
                logicalID: positionID,
                revisionID: positionRevisionID,
                createdBy: .user,
                inputs: positionInputs,
                evidence: [evidenceReference],
                at: at
            ),
            meetingID: meetingID,
            actorRevision: actorReference,
            representedEntityRevision: organizationReference,
            speakingCapacityRevision: capacityReference,
            issueRevision: issueReference,
            positionType: positionType,
            statement: statementClaim,
            effectiveTimeRange: effectiveTimeRange,
            comparisonState: .unknown,
            reviewStatus: .confirmed,
            userConfirmed: true
        )
        let position = try PositionV1(
            revision: envelope(
                logicalID: positionID,
                revisionID: positionRevisionID,
                createdBy: .user,
                inputs: positionInputs,
                evidence: [evidenceReference],
                semanticHash: positionDraft.calculatedSemanticContentHash(),
                published: true,
                at: at
            ),
            meetingID: meetingID,
            actorRevision: actorReference,
            representedEntityRevision: organizationReference,
            speakingCapacityRevision: capacityReference,
            issueRevision: issueReference,
            positionType: positionType,
            statement: statementClaim,
            effectiveTimeRange: effectiveTimeRange,
            comparisonState: .unknown,
            reviewStatus: .confirmed,
            userConfirmed: true
        )
        try store.insert(position)
        _ = try store.activate(
            ActivePublishedRevisionSelection(
                logicalID: position.positionID,
                revisionID: position.revision.revisionID
            ),
            as: PositionV1.self,
            expectedCurrentRevisionID: nil,
            markedAt: at
        )
        return StoredHistory(
            meeting: meeting,
            position: position,
            policy: security.accessPolicy
        )
    }

    static func positionCopy(
        _ source: PositionV1,
        positionID: PositionID,
        revisionID: RevisionID,
        at: UTCInstant
    ) throws -> PositionV1 {
        let draft = try PositionV1(
            revision: envelope(
                logicalID: positionID,
                revisionID: revisionID,
                createdBy: .user,
                inputs: source.revision.inputRevisions,
                evidence: source.revision.evidenceRevisions,
                at: at
            ),
            meetingID: source.meetingID,
            actorRevision: source.actorRevision,
            representedEntityRevision: source.representedEntityRevision,
            speakingCapacityRevision: source.speakingCapacityRevision,
            issueRevision: source.issueRevision,
            positionType: source.positionType,
            statement: source.statement,
            reservations: source.reservations,
            conditions: source.conditions,
            effectiveTimeRange: source.effectiveTimeRange,
            comparisonState: source.comparisonState,
            reviewStatus: source.reviewStatus,
            userConfirmed: source.userConfirmed
        )
        return try PositionV1(
            revision: envelope(
                logicalID: positionID,
                revisionID: revisionID,
                createdBy: .user,
                inputs: source.revision.inputRevisions,
                evidence: source.revision.evidenceRevisions,
                semanticHash: draft.calculatedSemanticContentHash(),
                published: true,
                at: at
            ),
            meetingID: source.meetingID,
            actorRevision: source.actorRevision,
            representedEntityRevision: source.representedEntityRevision,
            speakingCapacityRevision: source.speakingCapacityRevision,
            issueRevision: source.issueRevision,
            positionType: source.positionType,
            statement: source.statement,
            reservations: source.reservations,
            conditions: source.conditions,
            effectiveTimeRange: source.effectiveTimeRange,
            comparisonState: source.comparisonState,
            reviewStatus: source.reviewStatus,
            userConfirmed: source.userConfirmed
        )
    }
}

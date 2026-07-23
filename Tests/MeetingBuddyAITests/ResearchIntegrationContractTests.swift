import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import Testing

@Suite
struct ResearchIntegrationContractTests {
    @Test
    func researchWorkspaceIdentityIsDistinctInItsWireContract() throws {
        let workspace = try ResearchWorkspaceV1(
            workspaceID: cg1ID(1, ResearchWorkspaceID.self),
            kind: .meetingResearch,
            title: "Synthetic research collection",
            dataClassification: .internal
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace))
                as? [String: Any]
        )

        #expect(object["research_workspace_id"] != nil)
        #expect(object["workspace_id"] == nil)
    }

    @Test
    func sourceAdapterPreservesExactTruthAndNeverInfersAuthorityFromURL() throws {
        let source = try sourceAsset()
        let projection = try ResearchCompatibilityAdapters.sharedSource(
            from: source,
            authority: .unverified,
            completeness: .partial
        )
        let expectedRevision = try SemanticRevisionReference(
            logicalID: source.assetID,
            revisionID: source.revision.revisionID
        )

        #expect(projection.sourceRevision == expectedRevision)
        #expect(projection.authority == .unverified)
        #expect(projection.completeness == .partial)
        #expect(projection.canonicalKeyClaim == .unclaimed)
        #expect(projection.dataClassification == source.revision.dataClassification)
        #expect(projection.retentionClass == source.retentionClass)
        #expect(projection.contentDigest == source.sourceContentHash)
        #expect(projection.externalReference == source.sourceURL)
    }

    @Test
    func artifactAdaptersPreserveExactImmutableRevisions() throws {
        let firstBriefing = try finalBriefing(revisionSuffix: 31, title: "Briefing one")
        let secondBriefing = try finalBriefing(revisionSuffix: 32, title: "Briefing two")
        let firstProjection = try ResearchCompatibilityAdapters.artifactDescriptor(
            from: firstBriefing
        )
        let secondProjection = try ResearchCompatibilityAdapters.artifactDescriptor(
            from: secondBriefing
        )
        let comparison = try historicalComparison()
        let comparisonProjection = try ResearchCompatibilityAdapters.artifactDescriptor(
            from: comparison
        )

        #expect(
            firstProjection.currentVersion.exactSemanticRevision?.revisionID
                == firstBriefing.revision.revisionID
        )
        #expect(
            secondProjection.currentVersion.exactSemanticRevision?.revisionID
                == secondBriefing.revision.revisionID
        )
        #expect(
            firstProjection.currentVersion.exactSemanticRevision?.revisionID
                != secondProjection.currentVersion.exactSemanticRevision?.revisionID
        )
        #expect(firstProjection.title == "Briefing one")
        #expect(firstProjection.kind == .meetingBriefing)
        #expect(
            comparisonProjection.currentVersion.exactSemanticRevision?.revisionID
                == comparison.revision.revisionID
        )
        #expect(comparisonProjection.kind == .historicalComparison)
    }

    @Test
    func citationStoresOnlyAnExactEvidenceRevision() throws {
        let evidence = try evidenceRef()
        let evidenceRevision = try CitationAssociation.evidenceRevision(for: evidence)
        let citation = try CitationAssociation(
            target: .conversationMessage(
                conversationID: cg1ID(40, ConversationID.self),
                messageID: cg1ID(41, MessageID.self)
            ),
            evidenceRevision: evidenceRevision
        )
        let encoded = String(
            decoding: try JSONEncoder().encode(citation),
            as: UTF8.self
        )

        #expect(citation.evidenceRevision == evidenceRevision)
        #expect(!encoded.contains("location"))
        #expect(!encoded.contains("excerpt"))
        #expect(throws: DomainValidationError.self) {
            _ = try CitationAssociation(
                target: citation.target,
                evidenceRevision: sourceReference()
            )
        }
    }

    @Test
    func conversationHistoryAppendsWithoutMutatingPriorMessages() throws {
        let conversationID = cg1ID(50, ConversationID.self)
        let context = try ConversationContext(
            kind: .research,
            researchWorkspaceID: cg1ID(51, ResearchWorkspaceID.self),
            referencedRevisions: [],
            dataClassification: .sensitive
        )
        let first = try ConversationMessage(
            messageID: cg1ID(52, MessageID.self),
            conversationID: conversationID,
            sequence: 1,
            role: .user,
            content: "Compare the exact accepted revisions.",
            context: context,
            instructionSnapshotID: cg1ID(53, InstructionSnapshotID.self),
            createdAt: cg1Instant(100)
        )
        let second = try ConversationMessage(
            messageID: cg1ID(54, MessageID.self),
            conversationID: conversationID,
            sequence: 2,
            role: .assistant,
            content: "The comparison remains evidence-linked.",
            context: context,
            instructionSnapshotID: cg1ID(55, InstructionSnapshotID.self),
            createdAt: cg1Instant(101)
        )
        let original = try ConversationHistory(
            conversationID: conversationID,
            messages: [first]
        )
        let appended = try original.appending(second)

        #expect(original.messages == [first])
        #expect(appended.messages == [first, second])
        #expect(throws: DomainValidationError.self) {
            _ = try original.appending(
                ConversationMessage(
                    messageID: first.messageID,
                    conversationID: conversationID,
                    sequence: 2,
                    role: .assistant,
                    content: "Duplicate identity.",
                    context: context,
                    instructionSnapshotID: cg1ID(56, InstructionSnapshotID.self),
                    createdAt: cg1Instant(102)
                )
            )
        }
    }

    @Test
    func instructionCompilationProtectsPolicyAndIsDeterministic() throws {
        for protectedKey in [
            "classification.value",
            "citation.required",
            "diplomatic_rules.version",
            "evidence.required",
            "factual_rules.version",
            "human_confirmation.required",
            "network.offline",
            "policy.destination",
            "prompt_injection.isolation",
            "provider.identifier",
            "retention.mode",
            "tool_authority.value"
        ] {
            #expect(throws: DomainValidationError.self) {
                _ = try InstructionSetting(
                    key: protectedKey,
                    value: .text("override")
                )
            }
        }
        #expect(throws: DomainValidationError.self) {
            _ = try ProtectedInstructionPolicy(
                policyVersion: VersionedComponent(
                    identifier: "phase1-protected-policy",
                    version: "1"
                ),
                dataClassification: .internal,
                toolAuthority: .boundedReadOnly
            )
        }

        let global = try instructionProfile(
            suffix: 60,
            scope: .global,
            version: 1,
            settings: [
                InstructionSetting(key: "style.tone", value: .text("formal")),
                InstructionSetting(key: "output.concise", value: .boolean(false))
            ]
        )
        let request = try instructionProfile(
            suffix: 61,
            scope: .request,
            version: 1,
            settings: [
                InstructionSetting(key: "style.tone", value: .text("concise"))
            ]
        )
        let policy = try ProtectedInstructionPolicy(
            policyVersion: VersionedComponent(
                identifier: "phase1-protected-policy",
                version: "1"
            ),
            dataClassification: .sensitive
        )
        let module = try VersionedComponent(
            identifier: "diplomatic-factual-rules",
            version: "1"
        )
        let compiler = InstructionCompiler()
        let first = try compiler.compile(
            snapshotID: cg1ID(62, InstructionSnapshotID.self),
            protectedPolicy: policy,
            protectedRuleModules: [module],
            profiles: [request, global],
            createdAt: cg1Instant(110)
        )
        let repeated = try compiler.compile(
            snapshotID: first.snapshotID,
            protectedPolicy: policy,
            protectedRuleModules: [module],
            profiles: [global, request],
            createdAt: first.createdAt
        )
        let revisedRequest = try instructionProfile(
            suffix: 61,
            scope: .request,
            version: 2,
            settings: [
                InstructionSetting(key: "style.tone", value: .text("concise"))
            ]
        )
        let revised = try compiler.compile(
            snapshotID: cg1ID(63, InstructionSnapshotID.self),
            protectedPolicy: policy,
            protectedRuleModules: [module],
            profiles: [global, revisedRequest],
            createdAt: cg1Instant(111)
        )
        let tone = try #require(
            first.canonicalConfiguration.first { $0.key == "style.tone" }
        )
        let encoded = String(decoding: try JSONEncoder().encode(first), as: UTF8.self)

        #expect(tone.value == .text("concise"))
        #expect(first.configurationHash == repeated.configurationHash)
        #expect(first.configurationHash != revised.configurationHash)
        #expect(first.protectedPolicy.noOutboundMode)
        #expect(first.protectedPolicy.destination == .localDevice)
        #expect(!encoded.contains("compiled_prompt"))
        #expect(!encoded.contains("prompt_text"))
    }
}

private func instructionProfile(
    suffix: Int,
    scope: InstructionProfileScope,
    version: UInt32,
    settings: [InstructionSetting]
) throws -> InstructionProfile {
    try InstructionProfile(
        reference: InstructionProfileReference(
            profileID: cg1ID(suffix, InstructionProfileID.self),
            scope: scope,
            version: version
        ),
        settings: settings
    )
}

private func sourceAsset() throws -> SourceAssetV1 {
    let createdAt = cg1Instant(10)
    return try SourceAssetV1(
        revision: RevisionEnvelope(
            logicalID: cg1ID(10, SourceAssetID.self),
            revisionID: cg1ID(11, RevisionID.self),
            schemaVersion: .v1,
            lifecycleStatus: .draft,
            validationState: .notValidated,
            createdAt: createdAt,
            createdBy: .importProcess,
            dataClassification: .sensitive
        ),
        meetingID: cg1ID(12, MeetingID.self),
        assetType: .audio,
        originType: .approvedWebSource,
        sourceURL: HTTPSURL("https://official.example.invalid/meeting/audio"),
        managedStorageReference: ManagedAssetReference(
            storageObjectID: cg1ID(13, StorageObjectID.self)
        ),
        sourceContentHash: cg1Digest("a"),
        mimeType: MIMEType("audio/mpeg"),
        byteSize: 1_024,
        language: LanguageTag("en"),
        acquisitionMethod: .approvedHTTPSDownload,
        acquiredAt: cg1Instant(9),
        retentionClass: .permanent
    )
}

private func evidenceRef() throws -> EvidenceRefV1 {
    let source = try sourceReference()
    return try EvidenceRefV1(
        revision: RevisionEnvelope(
            logicalID: cg1ID(20, EvidenceID.self),
            revisionID: cg1ID(21, RevisionID.self),
            schemaVersion: .v1,
            lifecycleStatus: .draft,
            validationState: .notValidated,
            createdAt: cg1Instant(20),
            createdBy: .application,
            inputRevisions: [source],
            sourceAssetRevisions: [source],
            dataClassification: .internal
        ),
        location: .mediaTimeRange(
            source: source,
            range: MediaTimeRange(startMilliseconds: 0, endMilliseconds: 1_000)
        ),
        excerpt: EvidenceExcerpt(
            text: "Synthetic evidence.",
            language: LanguageTag("en"),
            translationStatus: .sourceOnly
        ),
        confidence: ConfidenceScore(millionths: 900_000)
    )
}

private func sourceReference() throws -> SemanticRevisionReference {
    try SemanticRevisionReference(
        logicalID: cg1ID(10, SourceAssetID.self),
        revisionID: cg1ID(11, RevisionID.self)
    )
}

private func finalBriefing(revisionSuffix: Int, title: String) throws -> FinalBriefingV1 {
    let meetingID = cg1ID(70, MeetingID.self)
    let meeting = try SemanticRevisionReference(
        logicalID: meetingID,
        revisionID: cg1ID(71, RevisionID.self)
    )
    let template = try SemanticRevisionReference(
        logicalID: cg1ID(72, BriefingTemplateID.self),
        revisionID: cg1ID(73, RevisionID.self)
    )
    let sections = try [
        (74, 75),
        (76, 77),
        (78, 79)
    ].map { logical, revision in
        try SemanticRevisionReference(
            logicalID: cg1ID(logical, BriefingSectionID.self),
            revisionID: cg1ID(revision, RevisionID.self)
        )
    }
    let report = try SemanticRevisionReference(
        logicalID: cg1ID(80, ValidationReportID.self),
        revisionID: cg1ID(81, RevisionID.self)
    )
    let evidence = try SemanticRevisionReference(
        logicalID: cg1ID(82, EvidenceID.self),
        revisionID: cg1ID(83, RevisionID.self)
    )
    let markdown = "# Synthetic briefing\n"
    return try FinalBriefingV1(
        revision: RevisionEnvelope(
            logicalID: cg1ID(30, FinalBriefingID.self),
            revisionID: cg1ID(revisionSuffix, RevisionID.self),
            schemaVersion: .v1,
            lifecycleStatus: .draft,
            validationState: .notValidated,
            createdAt: cg1Instant(30),
            createdBy: .application,
            inputRevisions: [meeting, template] + sections + [report],
            evidenceRevisions: [evidence],
            dataClassification: .internal
        ),
        meetingID: meetingID,
        templateRevision: template,
        sectionRevisions: sections,
        validationReportRevision: report,
        outputLanguage: LanguageTag("en"),
        documentTitle: title,
        renderer: VersionedComponent(identifier: "synthetic-renderer", version: "1"),
        markdown: markdown,
        markdownDigest: ContentDigest.sha256(ofUTF8Text: markdown),
        manualSectionCount: 0,
        reviewStatus: .unreviewed,
        userConfirmed: false
    )
}

private func historicalComparison() throws -> HistoricalComparisonV1 {
    let currentPosition = try cg1Reference(90, 91, PositionID.self)
    let historicalPosition = try cg1Reference(92, 93, PositionID.self)
    let currentMeeting = try cg1Reference(94, 95, MeetingID.self)
    let historicalMeeting = try cg1Reference(96, 97, MeetingID.self)
    let currentActor = try cg1Reference(98, 99, ActorID.self)
    let historicalActor = try cg1Reference(100, 101, ActorID.self)
    let currentIssue = try cg1Reference(102, 103, IssueID.self)
    let historicalIssue = try cg1Reference(104, 105, IssueID.self)
    let currentSensitivity = try cg1Reference(106, 107, SensitivityLabelID.self)
    let historicalSensitivity = try cg1Reference(108, 109, SensitivityLabelID.self)
    let currentAccess = try cg1Reference(110, 111, AccessPolicyID.self)
    let historicalAccess = try cg1Reference(112, 113, AccessPolicyID.self)
    let inputs = [
        currentPosition,
        historicalPosition,
        currentMeeting,
        historicalMeeting,
        currentActor,
        historicalActor,
        currentIssue,
        historicalIssue,
        currentSensitivity,
        historicalSensitivity,
        currentAccess,
        historicalAccess
    ]

    return try HistoricalComparisonV1(
        revision: RevisionEnvelope(
            logicalID: cg1ID(114, HistoricalComparisonID.self),
            revisionID: cg1ID(115, RevisionID.self),
            schemaVersion: .v1,
            lifecycleStatus: .draft,
            validationState: .notValidated,
            createdAt: cg1Instant(40),
            createdBy: .application,
            inputRevisions: inputs,
            dataClassification: .internal
        ),
        currentPositionRevision: currentPosition,
        historicalPositionRevision: historicalPosition,
        currentMeetingRevision: currentMeeting,
        historicalMeetingRevision: historicalMeeting,
        currentActorRevision: currentActor,
        historicalActorRevision: historicalActor,
        currentIssueRevision: currentIssue,
        historicalIssueRevision: historicalIssue,
        currentSensitivityLabelRevision: currentSensitivity,
        historicalSensitivityLabelRevision: historicalSensitivity,
        currentAccessPolicyRevision: currentAccess,
        historicalAccessPolicyRevision: historicalAccess,
        currentEffectiveDate: nil,
        historicalEffectiveDate: nil,
        currentEffectiveTimeRange: nil,
        historicalEffectiveTimeRange: nil,
        currentConfidence: ConfidenceScore(millionths: 500_000),
        historicalConfidence: ConfidenceScore(millionths: 500_000),
        currentEvidenceRevisions: [],
        historicalEvidenceRevisions: [],
        differenceState: .unknown,
        finding: .insufficientEvidence,
        reviewStatus: .unreviewed,
        userConfirmed: false
    )
}

private func cg1Reference<Tag: LogicalObjectIDScope>(
    _ logicalSuffix: Int,
    _ revisionSuffix: Int,
    _ type: StableID<Tag>.Type
) throws -> SemanticRevisionReference {
    try SemanticRevisionReference(
        logicalID: cg1ID(logicalSuffix, type),
        revisionID: cg1ID(revisionSuffix, RevisionID.self)
    )
}

private func cg1ID<Tag>(_ suffix: Int, _: StableID<Tag>.Type) -> StableID<Tag> {
    StableID(
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                suffix
            )
        )!
    )
}

private func cg1Instant(_ offset: Int64) -> UTCInstant {
    try! UTCInstant(millisecondsSinceUnixEpoch: 1_900_000_000_000 + offset)
}

private func cg1Digest(_ character: Character) -> ContentDigest {
    try! ContentDigest(
        algorithm: .sha256,
        lowercaseHex: String(repeating: character, count: 64)
    )
}

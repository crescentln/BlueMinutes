import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
@testable import MeetingBuddyPersistence

final class DisposableMeetingBuddyWorkspace: @unchecked Sendable {
    let container: URL
    let root: URL
    let sourceFile: URL
    let descriptor: LocalWorkspaceDescriptor
    let storage: LocalStorageService

    init(
        suffix: String = UUID().uuidString.lowercased(),
        workspaceID: WorkspaceID = PersistenceFixtures.workspaceID
    ) throws {
        container = FileManager.default.temporaryDirectory
            .appendingPathComponent("meetingbuddy-task004a-\(suffix)", isDirectory: true)
        root = container.appendingPathComponent("workspace", isDirectory: true)
        sourceFile = container.appendingPathComponent("authorized-source.bin")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        descriptor = try LocalWorkspaceService().createWorkspace(
            at: root,
            workspaceID: workspaceID,
            createdAt: PersistenceFixtures.createdAt
        )
        storage = LocalStorageService(workspace: descriptor)
    }

    func makeStore() throws -> SQLitePersistenceStore {
        try SQLitePersistenceStore(
            workspace: descriptor,
            migrationTimestamp: PersistenceFixtures.createdAt
        )
    }

    func writeSource(_ data: Data = PersistenceFixtures.sourceBytes) throws {
        try data.write(to: sourceFile, options: [.atomic])
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: container)
    }
}

enum PersistenceFixtures {
    static let workspaceID = id(1, WorkspaceID.self)
    static let meetingID = id(2, MeetingID.self)
    static let meetingRevisionID = id(3, RevisionID.self)
    static let replacementMeetingRevisionID = id(4, RevisionID.self)
    static let sourceAssetID = id(5, SourceAssetID.self)
    static let sourceRevisionID = id(6, RevisionID.self)
    static let storageObjectID = id(7, StorageObjectID.self)
    static let transcriptID = id(8, TranscriptSegmentID.self)
    static let transcriptRevisionID = id(9, RevisionID.self)
    static let translationID = id(10, TranslationSegmentID.self)
    static let translationRevisionID = id(11, RevisionID.self)
    static let actorID = id(12, ActorID.self)
    static let actorRevisionID = id(13, RevisionID.self)
    static let representedActorID = id(14, ActorID.self)
    static let representedActorRevisionID = id(15, RevisionID.self)
    static let capacityID = id(16, SpeakingCapacityID.self)
    static let capacityRevisionID = id(17, RevisionID.self)
    static let evidenceID = id(18, EvidenceID.self)
    static let evidenceRevisionID = id(19, RevisionID.self)
    static let assignmentID = id(20, SpeakerAssignmentID.self)
    static let assignmentRevisionID = id(21, RevisionID.self)
    static let agendaID = id(22, AgendaItemID.self)
    static let templateID = id(23, BriefingTemplateID.self)
    static let noteID = id(24, UserConfirmedNoteID.self)
    static let noteRevisionID = id(25, RevisionID.self)

    static let createdAt = try! UTCInstant(millisecondsSinceUnixEpoch: 1_750_000_000_000)
    static let acquiredAt = try! UTCInstant(millisecondsSinceUnixEpoch: 1_749_999_999_000)
    static let publishedAt = try! UTCInstant(millisecondsSinceUnixEpoch: 1_750_000_001_000)
    static let replacementPublishedAt = try! UTCInstant(millisecondsSinceUnixEpoch: 1_750_000_002_000)
    static let sourceBytes = Data("meetingbuddy-managed-asset-canary-004a".utf8)

    static func id<Tag>(_ suffix: Int, _ type: StableID<Tag>.Type) -> StableID<Tag> {
        let value = String(format: "40000000-0000-0000-0000-%012d", suffix)
        return StableID<Tag>(UUID(uuidString: value)!)
    }

    static func reference<Tag: LogicalObjectIDScope>(
        _ logicalID: StableID<Tag>,
        _ revisionID: RevisionID
    ) throws -> SemanticRevisionReference {
        try SemanticRevisionReference(logicalID: logicalID, revisionID: revisionID)
    }

    static func envelope<Tag: LogicalObjectIDScope>(
        logicalID: StableID<Tag>,
        revisionID: RevisionID,
        lifecycle: LifecycleStatus = .draft,
        validation: ValidationState = .notValidated,
        createdBy: CreationActor = .application,
        publishedAt: UTCInstant? = nil,
        supersedes: RevisionID? = nil,
        inputs: [SemanticRevisionReference] = [],
        sourceAssets: [SemanticRevisionReference] = [],
        evidence: [SemanticRevisionReference] = [],
        semanticHash: ContentDigest? = nil
    ) throws -> RevisionEnvelope<Tag> {
        try RevisionEnvelope(
            logicalID: logicalID,
            revisionID: revisionID,
            schemaVersion: .v1,
            lifecycleStatus: lifecycle,
            validationState: validation,
            createdAt: createdAt,
            createdBy: createdBy,
            publishedAt: publishedAt,
            supersedesRevisionID: supersedes,
            inputRevisions: inputs,
            sourceAssetRevisions: sourceAssets,
            evidenceRevisions: evidence,
            dataClassification: .internal,
            semanticContentHash: semanticHash
        )
    }

    static func managedAssetRecord(
        workspace: DisposableMeetingBuddyWorkspace
    ) throws -> ManagedAssetRecord {
        try workspace.writeSource()
        return try workspace.storage.storeFile(
            from: workspace.sourceFile,
            meetingID: meetingID,
            storageObjectID: storageObjectID,
            fileExtension: try ManagedFileExtension("bin"),
            createdAt: createdAt,
            dataClassification: .internal,
            retentionClass: .permanent
        )
    }

    static func sourceAsset(record: ManagedAssetRecord) throws -> SourceAssetV1 {
        try SourceAssetV1(
            revision: envelope(
                logicalID: sourceAssetID,
                revisionID: sourceRevisionID
            ),
            meetingID: meetingID,
            assetType: .document,
            originType: .localImport,
            managedStorageReference: ManagedAssetReference(storageObjectID: record.storageObjectID),
            sourceContentHash: record.contentHash,
            mimeType: MIMEType("application/octet-stream"),
            byteSize: record.byteSize,
            acquisitionMethod: .userSelectedFile,
            acquiredAt: acquiredAt,
            retentionClass: .permanent
        )
    }

    static func meetingProfile(
        revisionID: RevisionID = meetingRevisionID,
        title: String = "Synthetic Persistence Meeting",
        lifecycle: LifecycleStatus = .draft,
        validation: ValidationState = .notValidated,
        publishedAt: UTCInstant? = nil,
        supersedes: RevisionID? = nil,
        inputs: [SemanticRevisionReference] = [],
        semanticHash: ContentDigest? = nil,
        workspaceID: WorkspaceID = PersistenceFixtures.workspaceID
    ) throws -> MeetingProfileV1 {
        try MeetingProfileV1(
            revision: envelope(
                logicalID: meetingID,
                revisionID: revisionID,
                lifecycle: lifecycle,
                validation: validation,
                publishedAt: publishedAt,
                supersedes: supersedes,
                inputs: inputs,
                semanticHash: semanticHash
            ),
            title: title,
            meetingNumber: "SYN-004A",
            meetingDate: CalendarDate(year: 2026, month: 7, day: 18),
            organizationOrUNBody: .unresolved(label: "Synthetic Committee"),
            agendaItems: [
                AgendaItem(itemID: agendaID, ordinal: 1, title: "Persistence integrity")
            ],
            sourceLanguages: [LanguageTag("en")],
            outputLanguage: LanguageTag("zh-hans"),
            briefingTemplateID: templateID,
            cloudProcessingPolicy: .localOnly,
            workspaceID: workspaceID,
            reviewStatus: .unreviewed,
            userConfirmed: false
        )
    }

    static func publishedMeeting(
        revisionID: RevisionID,
        title: String,
        publishedAt: UTCInstant,
        supersedes: RevisionID? = nil
    ) throws -> MeetingProfileV1 {
        let draft = try meetingProfile(
            revisionID: revisionID,
            title: title,
            supersedes: supersedes
        )
        return try meetingProfile(
            revisionID: revisionID,
            title: title,
            lifecycle: .published,
            validation: .valid,
            publishedAt: publishedAt,
            supersedes: supersedes,
            semanticHash: draft.calculatedSemanticContentHash()
        )
    }

    static func transcript(
        source: SourceAssetV1,
        extraInputs: [SemanticRevisionReference] = []
    ) throws -> TranscriptSegmentV1 {
        let sourceReference = try reference(source.assetID, source.revision.revisionID)
        return try TranscriptSegmentV1(
            revision: envelope(
                logicalID: transcriptID,
                revisionID: transcriptRevisionID,
                inputs: [sourceReference] + extraInputs,
                sourceAssets: [sourceReference]
            ),
            meetingID: meetingID,
            sourceProvenance: .originalSpeakerAudio(sourceAssetRevision: sourceReference),
            timeRange: MediaTimeRange(startMilliseconds: 1_000, endMilliseconds: 4_000),
            detectedLanguage: LanguageTag("en"),
            text: "Synthetic source statement with exact evidence.",
            confidence: ConfidenceScore(millionths: 900_000),
            reviewStatus: .unreviewed,
            userConfirmed: false
        )
    }

    static func translation(transcript: TranscriptSegmentV1) throws -> TranslationSegmentV1 {
        let sourceReference = try reference(transcript.segmentID, transcript.revision.revisionID)
        return try TranslationSegmentV1(
            revision: envelope(
                logicalID: translationID,
                revisionID: translationRevisionID,
                createdBy: .user,
                inputs: [sourceReference]
            ),
            meetingID: meetingID,
            sourceSegmentRevision: sourceReference,
            sourceLanguage: LanguageTag("en"),
            targetLanguage: LanguageTag("zh-hans"),
            sourceTextHash: TranslationSegmentV1.calculateSourceTextHash(transcript.text),
            translatedText: "合成来源陈述，保留精确证据。",
            translationType: .humanTranslation,
            alignmentStatus: .aligned,
            confidence: ConfidenceScore(millionths: 950_000),
            reviewStatus: .unreviewed,
            userConfirmed: false
        )
    }

    static func actor(
        logicalID: ActorID = actorID,
        revisionID: RevisionID = actorRevisionID,
        identity: ActorIdentity = .person(
            displayName: "Synthetic Delegate",
            personName: "Alex Example"
        ),
        extraInputs: [SemanticRevisionReference] = []
    ) throws -> ActorV1 {
        try ActorV1(
            revision: envelope(
                logicalID: logicalID,
                revisionID: revisionID,
                inputs: extraInputs
            ),
            identity: identity,
            canonicalAliases: [identity.displayName],
            reviewStatus: .unreviewed,
            userConfirmed: false
        )
    }

    static func capacity(
        speaker: ActorV1,
        represented: ActorV1
    ) throws -> SpeakingCapacityV1 {
        let speakerReference = try reference(speaker.actorID, speaker.revision.revisionID)
        let representedReference = try reference(represented.actorID, represented.revision.revisionID)
        let relationship = try RepresentationRelationship(
            kind: .represents,
            entityRevision: representedReference
        )
        return try SpeakingCapacityV1(
            revision: envelope(
                logicalID: capacityID,
                revisionID: capacityRevisionID,
                inputs: [speakerReference, representedReference]
            ),
            meetingID: meetingID,
            speakerActorRevision: speakerReference,
            representationRelationships: [relationship],
            meetingRole: .delegate,
            reviewStatus: .unreviewed,
            userConfirmed: false
        )
    }

    static func evidence(transcript: TranscriptSegmentV1) throws -> EvidenceRefV1 {
        let transcriptReference = try reference(transcript.segmentID, transcript.revision.revisionID)
        return try EvidenceRefV1(
            revision: envelope(
                logicalID: evidenceID,
                revisionID: evidenceRevisionID,
                inputs: [transcriptReference]
            ),
            location: .transcriptSegment(
                source: transcriptReference,
                textRange: UTF8TextRange(
                    startOffset: 0,
                    length: UInt64(transcript.text.utf8.count)
                )
            ),
            excerpt: EvidenceExcerpt(
                text: transcript.text,
                language: LanguageTag("en"),
                translationStatus: .sourceOnly
            ),
            confidence: ConfidenceScore(millionths: 900_000)
        )
    }

    static func unresolvedNoteEvidence() throws -> EvidenceRefV1 {
        let noteReference = try reference(noteID, noteRevisionID)
        return try EvidenceRefV1(
            revision: envelope(
                logicalID: id(26, EvidenceID.self),
                revisionID: id(27, RevisionID.self),
                inputs: [noteReference]
            ),
            location: .userConfirmedNote(
                source: noteReference,
                textRange: UTF8TextRange(startOffset: 0, length: 12)
            ),
            excerpt: EvidenceExcerpt(
                text: "Synthetic note",
                language: LanguageTag("en"),
                translationStatus: .sourceOnly
            ),
            confidence: ConfidenceScore(millionths: 1_000_000)
        )
    }

    static func assignment(
        transcript: TranscriptSegmentV1,
        actor: ActorV1,
        capacity: SpeakingCapacityV1,
        evidence: EvidenceRefV1,
        extraInputs: [SemanticRevisionReference] = []
    ) throws -> SpeakerAssignmentV1 {
        let transcriptReference = try reference(transcript.segmentID, transcript.revision.revisionID)
        let actorReference = try reference(actor.actorID, actor.revision.revisionID)
        let capacityReference = try reference(capacity.capacityID, capacity.revision.revisionID)
        let evidenceReference = try reference(evidence.evidenceID, evidence.revision.revisionID)
        return try SpeakerAssignmentV1(
            revision: envelope(
                logicalID: assignmentID,
                revisionID: assignmentRevisionID,
                inputs: [transcriptReference, actorReference, capacityReference] + extraInputs,
                evidence: [evidenceReference]
            ),
            meetingID: meetingID,
            transcriptSegmentRevisions: [transcriptReference],
            actorRevision: actorReference,
            speakingCapacityRevision: capacityReference,
            confidence: ConfidenceScore(millionths: 800_000),
            certainty: .probable,
            assignmentSources: [.transcriptContext],
            reviewStatus: .unreviewed,
            userConfirmed: false
        )
    }
}

func expectCanonicalRoundTrip<Value: SemanticRevisionContract & Equatable>(
    _ value: Value,
    from store: SQLitePersistenceStore
) throws -> Bool {
    guard let loaded = try store.fetch(Value.self, revisionID: value.revision.revisionID) else {
        return false
    }
    let loadedBytes = try CanonicalJSON.encodeValidated(loaded)
    let expectedBytes = try CanonicalJSON.encodeValidated(value)
    return loaded == value && loadedBytes == expectedBytes
}

func posixMode(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

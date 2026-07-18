import CryptoKit
import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public enum AnalysisJobTypes {
    public static let pipeline = try! JobType("analysis-pipeline-v1")
}

public struct AnalysisPipelineJobPlan: Codable, Hashable, Sendable {
    public static let inputFormatIdentifier = "meetingbuddy.analysis-pipeline"
    public static let inputFormatVersion: UInt32 = 1

    public let meetingID: MeetingID
    public let meetingRevision: SemanticRevisionReference
    public let transcriptManifestID: TranscriptCoverageManifestID
    public let transcriptManifestHash: ContentDigest
    public let eligibleSegmentRevisions: [SemanticRevisionReference]
    public let analysisRoute: ModelRouteDecision
    public let runtimeEvidence: AnalysisRuntimeEvidence
    public let promptModules: [VersionedComponent]
    public let protectedRulesDigest: ContentDigest
    public let outputSchemaVersion: SchemaVersion
    public let inputPackageDigest: ContentDigest
    public let fixtureProvenance: AnalysisFixtureProvenance?
    public let ledgerID: AnalysisCoverageLedgerID
    public let createdAt: UTCInstant
    public let inputRevisionIDs: [SemanticRevisionReference]

    public init(
        source: AnalysisSourceBundle,
        analysisRoute: ModelRouteDecision,
        runtimeEvidence: AnalysisRuntimeEvidence,
        fixtureProvenance: AnalysisFixtureProvenance? = nil,
        createdAt: UTCInstant
    ) throws {
        let packages = try Self.requestPackages(from: source)
        let inputReferences = try Self.inputReferences(from: source)
        let packageDigest = try DiplomaticAnalysisPrompt.inputPackageDigest(
            requests: packages.map(\.request)
        )
        let segmentReferences = source.transcriptReview.manifest
            .transcriptRevisionReferences.sorted()
        let meetingReference = try Self.reference(source.meeting)
        guard source.transcriptReview.manifest.status == .published,
              analysisRoute.request.capability == .analysis,
              analysisRoute.route == .appleOnDevice
                || analysisRoute.route == .deterministicTest,
              analysisRoute.route.privacyRoute == .localOnly,
              analysisRoute.providerIdentifier != nil,
              runtimeEvidence.modelAvailable,
              runtimeEvidence.noOutboundMode,
              packages.map(\.request.transcriptRevision).sorted() == segmentReferences
        else {
            throw AIProviderContractError.invalidRequest(
                "The analysis plan requires a complete transcript and an available approved local route."
            )
        }
        meetingID = source.meeting.meetingID
        meetingRevision = meetingReference
        transcriptManifestID = source.transcriptReview.manifest.manifestID
        transcriptManifestHash = source.transcriptReview.manifest.contentHash
        eligibleSegmentRevisions = segmentReferences
        self.analysisRoute = analysisRoute
        self.runtimeEvidence = runtimeEvidence
        promptModules = DiplomaticAnalysisPrompt.modules
        protectedRulesDigest = DiplomaticAnalysisPrompt.protectedRulesDigest
        outputSchemaVersion = .v1
        inputPackageDigest = packageDigest
        self.fixtureProvenance = fixtureProvenance
        ledgerID = AnalysisCoverageLedgerID(
            Self.deterministicUUID(
                "task006a-ledger-v1:\(transcriptManifestID.canonicalString):\(packageDigest.lowercaseHex):\(analysisRoute.providerIdentifier ?? "manual")"
            )
        )
        self.createdAt = createdAt
        inputRevisionIDs = inputReferences
        try validate()
    }

    private init(validating decoded: Self) throws {
        self = decoded
        try validate()
    }

    public func validate() throws {
        let categories = Set(analysisRoute.request.dataCategories)
        guard meetingRevision.objectType == .meetingProfile,
              meetingRevision.logicalID.canonicalString == meetingID.canonicalString,
              !eligibleSegmentRevisions.isEmpty,
              eligibleSegmentRevisions.allSatisfy({ $0.objectType == .transcriptSegment }),
              Set(eligibleSegmentRevisions).count == eligibleSegmentRevisions.count,
              analysisRoute.request.capability == .analysis,
              analysisRoute.route == .appleOnDevice
                || analysisRoute.route == .deterministicTest,
              analysisRoute.route.privacyRoute == .localOnly,
              analysisRoute.providerIdentifier != nil,
              [.transcriptText, .speakerContext, .evidenceIdentifiers]
                .allSatisfy(categories.contains),
              runtimeEvidence.modelAvailable,
              runtimeEvidence.noOutboundMode,
              promptModules == DiplomaticAnalysisPrompt.modules,
              protectedRulesDigest == DiplomaticAnalysisPrompt.protectedRulesDigest,
              outputSchemaVersion == .v1,
              Set(inputRevisionIDs).count == inputRevisionIDs.count,
              inputRevisionIDs.contains(meetingRevision),
              Set(eligibleSegmentRevisions).isSubset(of: Set(inputRevisionIDs))
        else {
            throw AIProviderContractError.invalidRequest(
                "The persisted analysis plan failed route, prompt, or exact-input validation."
            )
        }
    }

    public func jobInputPayload() throws -> JobInputPayload {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try JobInputPayload(
            formatIdentifier: Self.inputFormatIdentifier,
            formatVersion: Self.inputFormatVersion,
            payload: encoder.encode(self)
        )
    }

    public static func decode(from input: JobInputPayload?) throws -> Self {
        guard let input,
              input.formatIdentifier == inputFormatIdentifier,
              input.formatVersion == inputFormatVersion
        else {
            throw AIProviderContractError.invalidRequest(
                "The analysis job payload is missing or unsupported."
            )
        }
        do {
            return try Self(validating: JSONDecoder().decode(Self.self, from: input.payload))
        } catch let error as AIProviderContractError {
            throw error
        } catch {
            throw AIProviderContractError.invalidRequest(
                "The analysis job payload could not be decoded."
            )
        }
    }

    public static func requestPackages(
        from source: AnalysisSourceBundle
    ) throws -> [(request: AnalysisRequest, resolved: AnalysisResolvedUnit)] {
        let actorByReference = try Dictionary(
            uniqueKeysWithValues: source.actors.map { (try reference($0), $0) }
        )
        let capacityByReference = try Dictionary(
            uniqueKeysWithValues: source.capacities.map { (try reference($0), $0) }
        )
        return try source.transcriptReview.transcriptSegments.sorted {
            $0.revision.revisionID < $1.revision.revisionID
        }.map { transcript in
            let transcriptReference = try reference(transcript)
            let assignments = source.transcriptReview.speakerAssignments.filter {
                $0.transcriptSegmentRevisions.contains(transcriptReference)
            }
            guard assignments.count == 1,
                  let assignment = assignments.first,
                  let actor = actorByReference[assignment.actorRevision],
                  let capacity = capacityByReference[assignment.speakingCapacityRevision]
            else {
                throw AIProviderContractError.invalidRequest(
                    "Each analysis segment needs exactly one resolved speaker assignment."
                )
            }
            let representedReferences = Array(
                Set(capacity.representationRelationships.map(\.entityRevision))
            ).sorted()
            guard representedReferences.count <= 1 else {
                throw AIProviderContractError.invalidRequest(
                    "A segment with multiple represented entities requires manual disambiguation."
                )
            }
            let represented = representedReferences.first.flatMap { actorByReference[$0] }
                ?? actor
            if representedReferences.first != nil,
               actorByReference[representedReferences[0]] == nil
            {
                throw AIProviderContractError.invalidRequest(
                    "The represented Actor revision was not resolved."
                )
            }
            let translations = source.transcriptReview.translations.filter {
                $0.sourceSegmentRevision == transcriptReference
            }
            guard translations.count <= 1 else {
                throw AIProviderContractError.invalidRequest(
                    "An analysis segment cannot select between duplicate translations."
                )
            }
            let translation = translations.first
            let resolved = try AnalysisResolvedUnit(
                meeting: source.meeting,
                transcript: transcript,
                translation: translation,
                speakerAssignment: assignment,
                speakerActor: actor,
                speakingCapacity: capacity,
                representedActor: represented,
                knownRecipientActors: source.actors
            )
            let evidenceKeys = assignment.revision.evidenceRevisions.map {
                "evidence_\($0.revisionID.canonicalString)"
            }
            let request = try AnalysisRequest(
                packageIdentifier: "segment_\(transcript.revision.revisionID.canonicalString)",
                transcriptRevision: transcriptReference,
                translationRevision: try translation.map(reference),
                speakerAssignmentRevision: try reference(assignment),
                transcriptText: transcript.text,
                translatedText: translation?.translatedText,
                speakerContext: AnalysisSpeakerContext(
                    actorLabel: actor.displayName,
                    capacityLabel: capacity.capacityLabel
                        ?? capacity.meetingRole.encodedValue.replacingOccurrences(of: "_", with: " "),
                    representedEntityLabel: represented.displayName,
                    assignmentIsConfirmed: assignment.certainty == .confirmed
                        && assignment.reviewStatus == .confirmed
                        && assignment.userConfirmed
                ),
                evidenceKeys: evidenceKeys,
                dataClassification: DataClassification.mostRestrictive([
                    transcript.revision.dataClassification,
                    translation?.revision.dataClassification,
                    assignment.revision.dataClassification,
                    actor.revision.dataClassification,
                    capacity.revision.dataClassification,
                    represented.revision.dataClassification
                ].compactMap { $0 }) ?? .restricted,
                localeIdentifier: source.meeting.outputLanguage.value
            )
            return (request, resolved)
        }
    }

    public static func inputReferences(
        from source: AnalysisSourceBundle
    ) throws -> [SemanticRevisionReference] {
        var references = [try reference(source.meeting)]
        references += try source.transcriptReview.transcriptSegments.map(reference)
        references += try source.transcriptReview.translations.map(reference)
        references += try source.transcriptReview.speakerAssignments.map(reference)
        references += try source.sourceAssets.map(reference)
        references += try source.actors.map(reference)
        references += try source.capacities.map(reference)
        return Array(Set(references)).sorted()
    }

    private static func reference<Object: SemanticRevisionContract>(
        _ value: Object
    ) throws -> SemanticRevisionReference {
        try SemanticRevisionReference(
            logicalID: value.revision.logicalID,
            revisionID: value.revision.revisionID
        )
    }

    private static func deterministicUUID(_ seed: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

public struct AnalysisPipelineJobFactory: Sendable {
    public init() {}

    public func request(
        plan: AnalysisPipelineJobPlan,
        jobID: JobID = JobID(UUID()),
        requestedBy: JobRequester,
        maximumRetryCount: UInt32 = 2
    ) throws -> JobRequest {
        try plan.validate()
        let input = try plan.jobInputPayload()
        let digest = SHA256.hash(data: input.payload)
            .map { String(format: "%02x", $0) }
            .joined()
        return try JobRequest(
            jobID: jobID,
            jobType: AnalysisJobTypes.pipeline,
            meetingID: plan.meetingID,
            origin: .user,
            requestedBy: requestedBy,
            inputPayload: input,
            inputRevisionIDs: plan.inputRevisionIDs,
            privacyRoute: .localOnly,
            dataClassification: plan.analysisRoute.request.dataClassification,
            idempotencyKey: JobIdempotencyKey(lowercaseHex: digest),
            resumeCapability: .restartOnly,
            maximumRetryCount: maximumRetryCount,
            totalUnitCount: UInt64(plan.eligibleSegmentRevisions.count),
            diskBudgetBytes: 8 * 1_024 * 1_024
        )
    }
}

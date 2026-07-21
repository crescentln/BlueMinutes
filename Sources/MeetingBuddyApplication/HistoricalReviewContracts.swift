import Foundation
import MeetingBuddyDomain

public enum HistoricalReviewError: Error, Equatable, Sendable {
    case invalidQuery(String)
    case indexDisabled
    case indexRebuildRequired
    case accessDenied
    case sourceUnavailable(RevisionID)
    case comparisonNotAllowed(String)
    case preferenceConflict(LearnedPreferenceID)
    case preferenceNotFound(LearnedPreferenceID)
    case invalidPreference(String)
}

public enum HistoricalEvidenceSourceKind: String, Codable, Hashable, Sendable {
    case versionedDocument = "versioned_document"
    case permittedEmailImport = "permitted_email_import"
    case permittedPublicSource = "permitted_public_source"
}

/// Content-only provenance for evidence already admitted by a separately
/// authorized local/import adapter. This contract grants no file, mail, or
/// network authority and never interprets imported text as instructions.
public struct HistoricalEvidenceSourceDescriptor: Codable, Hashable, Sendable {
    public let kind: HistoricalEvidenceSourceKind
    public let sourceAssetRevision: SemanticRevisionReference
    public let sourceContentHash: ContentDigest
    public let byteSize: UInt64
    public let acquiredAt: UTCInstant
    public let remoteResourcesDisabled: Bool

    public init(
        kind: HistoricalEvidenceSourceKind,
        sourceAssetRevision: SemanticRevisionReference,
        sourceContentHash: ContentDigest,
        byteSize: UInt64,
        acquiredAt: UTCInstant,
        remoteResourcesDisabled: Bool
    ) throws {
        guard sourceAssetRevision.objectType == .sourceAsset,
              sourceContentHash.algorithm == .sha256,
              byteSize > 0,
              remoteResourcesDisabled || kind == .permittedPublicSource
        else {
            throw HistoricalReviewError.comparisonNotAllowed(
                "Historical evidence provenance is incomplete or unsafe."
            )
        }
        self.kind = kind
        self.sourceAssetRevision = sourceAssetRevision
        self.sourceContentHash = sourceContentHash
        self.byteSize = byteSize
        self.acquiredAt = acquiredAt
        self.remoteResourcesDisabled = remoteResourcesDisabled
    }
}

public enum HistoricalEvidenceAdmission {
    public static func validate(
        _ descriptor: HistoricalEvidenceSourceDescriptor,
        sourceAsset: SourceAssetV1
    ) throws {
        let reference = try SemanticRevisionReference(
            logicalID: sourceAsset.assetID,
            revisionID: sourceAsset.revision.revisionID
        )
        guard descriptor.sourceAssetRevision == reference,
              descriptor.sourceContentHash == sourceAsset.sourceContentHash,
              descriptor.byteSize == sourceAsset.byteSize,
              descriptor.acquiredAt == sourceAsset.acquiredAt,
              sourceAsset.assetType == .document,
              sourceAsset.revision.lifecycleStatus == .published,
              sourceAsset.revision.validationState == .valid,
              sourceAsset.revision.semanticContentHash != nil
        else {
            throw HistoricalReviewError.comparisonNotAllowed(
                "Evidence integrity metadata does not match the exact SourceAsset revision."
            )
        }
        switch descriptor.kind {
        case .versionedDocument:
            guard sourceAsset.originType == .localImport,
                  sourceAsset.acquisitionMethod == .userSelectedFile,
                  sourceAsset.managedStorageReference != nil,
                  descriptor.remoteResourcesDisabled
            else { throw HistoricalReviewError.accessDenied }
        case .permittedEmailImport:
            guard sourceAsset.originType == .localImport,
                  sourceAsset.acquisitionMethod == .userSelectedFile,
                  sourceAsset.managedStorageReference != nil,
                  sourceAsset.sourceURL == nil,
                  descriptor.remoteResourcesDisabled
            else { throw HistoricalReviewError.accessDenied }
        case .permittedPublicSource:
            guard sourceAsset.originType == .approvedWebSource,
                  sourceAsset.acquisitionMethod == .approvedHTTPSDownload,
                  sourceAsset.sourceURL != nil
            else { throw HistoricalReviewError.accessDenied }
        }
    }
}

public enum HistoricalIndexAvailability: String, Codable, Hashable, Sendable {
    case ready
    case rebuildRequired = "rebuild_required"
    case disabled
}

public struct HistoricalIndexStatus: Codable, Hashable, Sendable {
    public let availability: HistoricalIndexAvailability
    public let generation: UInt64
    public let normalizerVersion: UInt32
    public let indexedPositionCount: UInt64
    public let rebuiltAt: UTCInstant?
    public let sourceFingerprint: ContentDigest?

    public init(
        availability: HistoricalIndexAvailability,
        generation: UInt64,
        normalizerVersion: UInt32,
        indexedPositionCount: UInt64,
        rebuiltAt: UTCInstant?,
        sourceFingerprint: ContentDigest?
    ) {
        self.availability = availability
        self.generation = generation
        self.normalizerVersion = normalizerVersion
        self.indexedPositionCount = indexedPositionCount
        self.rebuiltAt = rebuiltAt
        self.sourceFingerprint = sourceFingerprint
    }
}

public struct HistoricalIndexRebuildReport: Codable, Hashable, Sendable {
    public let previousGeneration: UInt64
    public let replacementGeneration: UInt64
    public let indexedPositionCount: UInt64
    public let skippedUnconfirmedPositionCount: UInt64
    public let skippedUnsafePositionCount: UInt64
    public let sourceFingerprint: ContentDigest
    public let completedAt: UTCInstant

    public init(
        previousGeneration: UInt64,
        replacementGeneration: UInt64,
        indexedPositionCount: UInt64,
        skippedUnconfirmedPositionCount: UInt64,
        skippedUnsafePositionCount: UInt64,
        sourceFingerprint: ContentDigest,
        completedAt: UTCInstant
    ) {
        self.previousGeneration = previousGeneration
        self.replacementGeneration = replacementGeneration
        self.indexedPositionCount = indexedPositionCount
        self.skippedUnconfirmedPositionCount = skippedUnconfirmedPositionCount
        self.skippedUnsafePositionCount = skippedUnsafePositionCount
        self.sourceFingerprint = sourceFingerprint
        self.completedAt = completedAt
    }
}

public struct HistoricalSearchCursor: Codable, Hashable, Sendable {
    public let indexGeneration: UInt64
    public let effectiveDate: CalendarDate?
    public let mediaStartMilliseconds: Int64?
    public let positionRevisionID: RevisionID

    public init(
        indexGeneration: UInt64,
        effectiveDate: CalendarDate?,
        mediaStartMilliseconds: Int64?,
        positionRevisionID: RevisionID
    ) {
        self.indexGeneration = indexGeneration
        self.effectiveDate = effectiveDate
        self.mediaStartMilliseconds = mediaStartMilliseconds
        self.positionRevisionID = positionRevisionID
    }
}

public struct HistoricalSearchQuery: Hashable, Sendable {
    public let actorOrCountry: String?
    public let topic: String?
    public let organization: String?
    public let meetingBody: String?
    public let meetingType: String?
    public let issue: String?
    public let startDate: CalendarDate?
    public let endDate: CalendarDate?
    public let reviewStatus: ReviewStatus?
    public let maximumClassification: DataClassification
    public let cursor: HistoricalSearchCursor?
    public let pageSize: UInt32

    public init(
        actorOrCountry: String? = nil,
        topic: String? = nil,
        organization: String? = nil,
        meetingBody: String? = nil,
        meetingType: String? = nil,
        issue: String? = nil,
        startDate: CalendarDate? = nil,
        endDate: CalendarDate? = nil,
        reviewStatus: ReviewStatus? = .confirmed,
        maximumClassification: DataClassification = .restricted,
        cursor: HistoricalSearchCursor? = nil,
        pageSize: UInt32 = 50
    ) throws {
        let hasInvertedDateRange: Bool
        if let startDate, let endDate {
            hasInvertedDateRange = startDate > endDate
        } else {
            hasInvertedDateRange = false
        }
        guard (1 ... 100).contains(pageSize),
              maximumClassification.isKnown,
              reviewStatus?.isKnown != false,
              !hasInvertedDateRange
        else {
            throw HistoricalReviewError.invalidQuery("Search bounds or stable values are invalid.")
        }
        let values = [actorOrCountry, topic, organization, meetingBody, meetingType, issue]
        guard values.compactMap({ $0 }).allSatisfy({ value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed.utf8.count <= 512 && !trimmed.contains("\u{0}")
        }) else {
            throw HistoricalReviewError.invalidQuery("Search filters must be bounded non-empty text.")
        }
        self.actorOrCountry = actorOrCountry
        self.topic = topic
        self.organization = organization
        self.meetingBody = meetingBody
        self.meetingType = meetingType
        self.issue = issue
        self.startDate = startDate
        self.endDate = endDate
        self.reviewStatus = reviewStatus
        self.maximumClassification = maximumClassification
        self.cursor = cursor
        self.pageSize = pageSize
    }
}

public struct HistoricalPositionResult: Identifiable, Hashable, Sendable {
    public let position: PositionV1
    public let meeting: MeetingProfileV1
    public let actor: ActorV1
    public let issue: IssueV1
    public let evidence: [EvidenceRefV1]
    public let sensitivityLabelRevision: SemanticRevisionReference
    public let accessPolicyRevision: SemanticRevisionReference
    public let organizationLabel: String?
    public let meetingType: MeetingTemplateType?
    public let effectiveClassification: DataClassification

    public var id: String { position.revision.revisionID.canonicalString }

    public init(
        position: PositionV1,
        meeting: MeetingProfileV1,
        actor: ActorV1,
        issue: IssueV1,
        evidence: [EvidenceRefV1],
        sensitivityLabelRevision: SemanticRevisionReference,
        accessPolicyRevision: SemanticRevisionReference,
        organizationLabel: String?,
        meetingType: MeetingTemplateType?,
        effectiveClassification: DataClassification
    ) {
        self.position = position
        self.meeting = meeting
        self.actor = actor
        self.issue = issue
        self.evidence = evidence.sorted { $0.revision.revisionID < $1.revision.revisionID }
        self.sensitivityLabelRevision = sensitivityLabelRevision
        self.accessPolicyRevision = accessPolicyRevision
        self.organizationLabel = organizationLabel
        self.meetingType = meetingType
        self.effectiveClassification = effectiveClassification
    }

    public func cursor(indexGeneration: UInt64) -> HistoricalSearchCursor {
        HistoricalSearchCursor(
            indexGeneration: indexGeneration,
            effectiveDate: meeting.meetingDate,
            mediaStartMilliseconds: position.effectiveTimeRange?.startMilliseconds,
            positionRevisionID: position.revision.revisionID
        )
    }
}

public struct HistoricalSearchPage: Hashable, Sendable {
    public let results: [HistoricalPositionResult]
    public let nextCursor: HistoricalSearchCursor?
    public let indexGeneration: UInt64

    public init(
        results: [HistoricalPositionResult],
        nextCursor: HistoricalSearchCursor?,
        indexGeneration: UInt64
    ) {
        self.results = results
        self.nextCursor = nextCursor
        self.indexGeneration = indexGeneration
    }
}

public struct HistoricalComparisonEvaluation: Hashable, Sendable {
    public let current: HistoricalPositionResult
    public let historical: HistoricalPositionResult
    public let differenceState: HistoricalDifferenceState
    public let finding: HistoricalFinding

    public init(
        current: HistoricalPositionResult,
        historical: HistoricalPositionResult,
        differenceState: HistoricalDifferenceState,
        finding: HistoricalFinding
    ) {
        self.current = current
        self.historical = historical
        self.differenceState = differenceState
        self.finding = finding
    }

    public var qualifiedSummary: String { finding.qualifiedSummary }
}

public enum HistoricalComparisonEvaluator {
    public static func evaluate(
        current: HistoricalPositionResult,
        historical: HistoricalPositionResult
    ) -> HistoricalComparisonEvaluation {
        guard qualifies(current), qualifies(historical),
              sameActor(current, historical), sameTopic(current, historical),
              let currentDate = current.meeting.meetingDate,
              let historicalDate = historical.meeting.meetingDate,
              currentDate > historicalDate,
              !current.position.revision.evidenceRevisions.isEmpty,
              !historical.position.revision.evidenceRevisions.isEmpty
        else {
            return HistoricalComparisonEvaluation(
                current: current,
                historical: historical,
                differenceState: .insufficientEvidence,
                finding: .insufficientEvidence
            )
        }

        let currentPosition = current.position
        let historicalPosition = historical.position
        let currentReservations = normalizedClaims(currentPosition.reservations)
        let historicalReservations = normalizedClaims(historicalPosition.reservations)
        let currentConditions = normalizedClaims(currentPosition.conditions)
        let historicalConditions = normalizedClaims(historicalPosition.conditions)

        if currentPosition.positionType == historicalPosition.positionType,
           currentReservations == historicalReservations,
           currentConditions == historicalConditions
        {
            let finding: HistoricalFinding = normalize(currentPosition.statement.text)
                == normalize(historicalPosition.statement.text)
                ? .repeatedPosition : .wordingOnlyDifference
            return HistoricalComparisonEvaluation(
                current: current,
                historical: historical,
                differenceState: .noConfirmedDifference,
                finding: finding
            )
        }

        if Set(currentReservations).isStrictSuperset(of: Set(historicalReservations)) {
            return HistoricalComparisonEvaluation(
                current: current,
                historical: historical,
                differenceState: .possibleDifference,
                finding: .possibleNewReservation
            )
        }
        return HistoricalComparisonEvaluation(
            current: current,
            historical: historical,
            differenceState: .possibleDifference,
            finding: .possibleChange
        )
    }

    private static func qualifies(_ result: HistoricalPositionResult) -> Bool {
        let revision = result.position.revision
        return revision.lifecycleStatus == .published
            && revision.validationState == .valid
            && result.position.reviewStatus == .confirmed
            && result.position.userConfirmed
    }

    private static func sameActor(
        _ lhs: HistoricalPositionResult,
        _ rhs: HistoricalPositionResult
    ) -> Bool {
        if lhs.position.actorRevision.logicalID == rhs.position.actorRevision.logicalID {
            return true
        }
        guard let lhsCode = lhs.actor.identity.countryCode,
              let rhsCode = rhs.actor.identity.countryCode
        else { return false }
        return lhsCode == rhsCode
    }

    private static func sameTopic(
        _ lhs: HistoricalPositionResult,
        _ rhs: HistoricalPositionResult
    ) -> Bool {
        lhs.position.issueRevision.logicalID == rhs.position.issueRevision.logicalID
            || normalize(lhs.issue.title.text) == normalize(rhs.issue.title.text)
    }

    private static func normalizedClaims(_ claims: [EvidenceLinkedClaim]) -> [String] {
        claims.map { normalize($0.text) }.sorted()
    }

    public static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

public enum HistoricalComparisonFactory {
    public static func candidate(
        evaluation: HistoricalComparisonEvaluation,
        comparisonID: HistoricalComparisonID = HistoricalComparisonID(UUID()),
        revisionID: RevisionID = RevisionID(UUID()),
        createdAt: UTCInstant
    ) throws -> HistoricalComparisonV1 {
        let current = evaluation.current
        let historical = evaluation.historical
        let inputs = try inputReferences(current: current, historical: historical)
        let evidence = Array(Set(
            current.position.revision.evidenceRevisions
                + historical.position.revision.evidenceRevisions
        )).sorted()
        let classification = DataClassification.mostRestrictive([
            current.effectiveClassification, historical.effectiveClassification
        ]) ?? .restricted
        let draftEnvelope = try RevisionEnvelope<HistoricalComparisonIDTag>(
            logicalID: comparisonID,
            revisionID: revisionID,
            schemaVersion: .v1,
            lifecycleStatus: .draft,
            validationState: .notValidated,
            createdAt: createdAt,
            createdBy: .application,
            inputRevisions: inputs,
            evidenceRevisions: evidence,
            dataClassification: classification
        )
        let draft = try comparison(
            revision: draftEnvelope,
            evaluation: evaluation,
            confirmationOfRevision: nil,
            reviewStatus: .needsReview,
            userConfirmed: false
        )
        let publishedEnvelope = try RevisionEnvelope<HistoricalComparisonIDTag>(
            logicalID: comparisonID,
            revisionID: revisionID,
            schemaVersion: .v1,
            lifecycleStatus: .published,
            validationState: .valid,
            createdAt: createdAt,
            createdBy: .application,
            publishedAt: createdAt,
            inputRevisions: inputs,
            evidenceRevisions: evidence,
            dataClassification: classification,
            semanticContentHash: draft.calculatedSemanticContentHash()
        )
        return try comparison(
            revision: publishedEnvelope,
            evaluation: evaluation,
            confirmationOfRevision: nil,
            reviewStatus: .needsReview,
            userConfirmed: false
        )
    }

    public static func confirmedChange(
        candidate: HistoricalComparisonV1,
        revisionID: RevisionID = RevisionID(UUID()),
        confirmedAt: UTCInstant
    ) throws -> HistoricalComparisonV1 {
        guard candidate.differenceState == .possibleDifference else {
            throw HistoricalReviewError.comparisonNotAllowed(
                "Only a possible evidence-linked difference can be confirmed."
            )
        }
        let candidateReference = try SemanticRevisionReference(
            logicalID: candidate.comparisonID,
            revisionID: candidate.revision.revisionID
        )
        let inputs = (candidate.revision.inputRevisions + [candidateReference]).sorted()
        let draftEnvelope = try RevisionEnvelope<HistoricalComparisonIDTag>(
            logicalID: candidate.comparisonID,
            revisionID: revisionID,
            schemaVersion: .v1,
            lifecycleStatus: .draft,
            validationState: .notValidated,
            createdAt: confirmedAt,
            createdBy: .user,
            supersedesRevisionID: candidate.revision.revisionID,
            inputRevisions: inputs,
            evidenceRevisions: candidate.revision.evidenceRevisions,
            dataClassification: candidate.revision.dataClassification
        )
        let draft = try confirmedComparison(
            candidate: candidate,
            revision: draftEnvelope,
            candidateReference: candidateReference
        )
        let publishedEnvelope = try RevisionEnvelope<HistoricalComparisonIDTag>(
            logicalID: candidate.comparisonID,
            revisionID: revisionID,
            schemaVersion: .v1,
            lifecycleStatus: .published,
            validationState: .valid,
            createdAt: confirmedAt,
            createdBy: .user,
            publishedAt: confirmedAt,
            supersedesRevisionID: candidate.revision.revisionID,
            inputRevisions: inputs,
            evidenceRevisions: candidate.revision.evidenceRevisions,
            dataClassification: candidate.revision.dataClassification,
            semanticContentHash: draft.calculatedSemanticContentHash()
        )
        return try confirmedComparison(
            candidate: candidate,
            revision: publishedEnvelope,
            candidateReference: candidateReference
        )
    }

    private static func inputReferences(
        current: HistoricalPositionResult,
        historical: HistoricalPositionResult
    ) throws -> [SemanticRevisionReference] {
        Array(Set([
            try SemanticRevisionReference(logicalID: current.position.positionID, revisionID: current.position.revision.revisionID),
            try SemanticRevisionReference(logicalID: historical.position.positionID, revisionID: historical.position.revision.revisionID),
            try SemanticRevisionReference(logicalID: current.meeting.meetingID, revisionID: current.meeting.revision.revisionID),
            try SemanticRevisionReference(logicalID: historical.meeting.meetingID, revisionID: historical.meeting.revision.revisionID),
            current.position.actorRevision,
            historical.position.actorRevision,
            current.position.issueRevision,
            historical.position.issueRevision,
            current.sensitivityLabelRevision,
            historical.sensitivityLabelRevision,
            current.accessPolicyRevision,
            historical.accessPolicyRevision
        ])).sorted()
    }

    private static func comparison(
        revision: RevisionEnvelope<HistoricalComparisonIDTag>,
        evaluation: HistoricalComparisonEvaluation,
        confirmationOfRevision: SemanticRevisionReference?,
        reviewStatus: ReviewStatus,
        userConfirmed: Bool
    ) throws -> HistoricalComparisonV1 {
        try HistoricalComparisonV1(
            revision: revision,
            currentPositionRevision: SemanticRevisionReference(logicalID: evaluation.current.position.positionID, revisionID: evaluation.current.position.revision.revisionID),
            historicalPositionRevision: SemanticRevisionReference(logicalID: evaluation.historical.position.positionID, revisionID: evaluation.historical.position.revision.revisionID),
            currentMeetingRevision: SemanticRevisionReference(logicalID: evaluation.current.meeting.meetingID, revisionID: evaluation.current.meeting.revision.revisionID),
            historicalMeetingRevision: SemanticRevisionReference(logicalID: evaluation.historical.meeting.meetingID, revisionID: evaluation.historical.meeting.revision.revisionID),
            currentActorRevision: evaluation.current.position.actorRevision,
            historicalActorRevision: evaluation.historical.position.actorRevision,
            currentIssueRevision: evaluation.current.position.issueRevision,
            historicalIssueRevision: evaluation.historical.position.issueRevision,
            currentSensitivityLabelRevision: evaluation.current.sensitivityLabelRevision,
            historicalSensitivityLabelRevision: evaluation.historical.sensitivityLabelRevision,
            currentAccessPolicyRevision: evaluation.current.accessPolicyRevision,
            historicalAccessPolicyRevision: evaluation.historical.accessPolicyRevision,
            currentEffectiveDate: evaluation.current.meeting.meetingDate,
            historicalEffectiveDate: evaluation.historical.meeting.meetingDate,
            currentEffectiveTimeRange: evaluation.current.position.effectiveTimeRange,
            historicalEffectiveTimeRange: evaluation.historical.position.effectiveTimeRange,
            currentConfidence: evaluation.current.position.statement.confidence,
            historicalConfidence: evaluation.historical.position.statement.confidence,
            currentEvidenceRevisions: evaluation.current.position.revision.evidenceRevisions,
            historicalEvidenceRevisions: evaluation.historical.position.revision.evidenceRevisions,
            differenceState: evaluation.differenceState,
            finding: evaluation.finding,
            confirmationOfRevision: confirmationOfRevision,
            reviewStatus: reviewStatus,
            userConfirmed: userConfirmed
        )
    }

    private static func confirmedComparison(
        candidate: HistoricalComparisonV1,
        revision: RevisionEnvelope<HistoricalComparisonIDTag>,
        candidateReference: SemanticRevisionReference
    ) throws -> HistoricalComparisonV1 {
        try HistoricalComparisonV1(
            revision: revision,
            currentPositionRevision: candidate.currentPositionRevision,
            historicalPositionRevision: candidate.historicalPositionRevision,
            currentMeetingRevision: candidate.currentMeetingRevision,
            historicalMeetingRevision: candidate.historicalMeetingRevision,
            currentActorRevision: candidate.currentActorRevision,
            historicalActorRevision: candidate.historicalActorRevision,
            currentIssueRevision: candidate.currentIssueRevision,
            historicalIssueRevision: candidate.historicalIssueRevision,
            currentSensitivityLabelRevision: candidate.currentSensitivityLabelRevision,
            historicalSensitivityLabelRevision: candidate.historicalSensitivityLabelRevision,
            currentAccessPolicyRevision: candidate.currentAccessPolicyRevision,
            historicalAccessPolicyRevision: candidate.historicalAccessPolicyRevision,
            currentEffectiveDate: candidate.currentEffectiveDate,
            historicalEffectiveDate: candidate.historicalEffectiveDate,
            currentEffectiveTimeRange: candidate.currentEffectiveTimeRange,
            historicalEffectiveTimeRange: candidate.historicalEffectiveTimeRange,
            currentConfidence: candidate.currentConfidence,
            historicalConfidence: candidate.historicalConfidence,
            currentEvidenceRevisions: candidate.currentEvidenceRevisions,
            historicalEvidenceRevisions: candidate.historicalEvidenceRevisions,
            differenceState: .userConfirmedDifference,
            finding: .userConfirmedChange,
            confirmationOfRevision: candidateReference,
            reviewStatus: .confirmed,
            userConfirmed: true
        )
    }
}

public enum LearnedPreferenceKind: String, Codable, CaseIterable, Hashable, Sendable {
    case actorCountryOrder = "actor_country_order"
    case briefingLength = "briefing_length"
    case sectionOrder = "section_order"
    case quotationPolicy = "quotation_policy"
    case grouping
    case terminology
    case frequentTemplates = "frequent_templates"
}

public enum LearnedQuotationPolicy: String, Codable, Hashable, Sendable {
    case exactOnly = "exact_only"
    case exactWithTranslation = "exact_with_translation"
    case paraphraseWithEvidence = "paraphrase_with_evidence"
}

public enum LearnedGrouping: String, Codable, Hashable, Sendable {
    case byActor = "by_actor"
    case byIssue = "by_issue"
    case chronological
}

public struct TerminologyPreference: Codable, Hashable, Sendable, Comparable {
    public let sourceTerm: String
    public let displayTerm: String

    public init(sourceTerm: String, displayTerm: String) throws {
        let values = [sourceTerm, displayTerm]
        guard values.allSatisfy({ value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return value == trimmed
                && !trimmed.isEmpty
                && trimmed.utf8.count <= 256
                && trimmed.rangeOfCharacter(from: .controlCharacters) == nil
        }) else {
            throw HistoricalReviewError.invalidPreference("Terminology must be bounded non-empty text.")
        }
        self.sourceTerm = sourceTerm
        self.displayTerm = displayTerm
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.sourceTerm, lhs.displayTerm) < (rhs.sourceTerm, rhs.displayTerm)
    }
}

public enum LearnedPreferenceValue: Codable, Hashable, Sendable {
    case actorCountryOrder([String])
    case briefingLength(UInt32)
    case sectionOrder([BriefingSectionType])
    case quotationPolicy(LearnedQuotationPolicy)
    case grouping(LearnedGrouping)
    case terminology([TerminologyPreference])
    case frequentTemplates([BriefingTemplateID])

    public var kind: LearnedPreferenceKind {
        switch self {
        case .actorCountryOrder: .actorCountryOrder
        case .briefingLength: .briefingLength
        case .sectionOrder: .sectionOrder
        case .quotationPolicy: .quotationPolicy
        case .grouping: .grouping
        case .terminology: .terminology
        case .frequentTemplates: .frequentTemplates
        }
    }

    public func validate() throws {
        switch self {
        case let .actorCountryOrder(values):
            guard !values.isEmpty, values.count <= 256, Set(values).count == values.count,
                  values.allSatisfy({ value in
                      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                      return value == trimmed
                          && !trimmed.isEmpty
                          && value.utf8.count <= 512
                          && value.rangeOfCharacter(from: .controlCharacters) == nil
                  })
            else { throw HistoricalReviewError.invalidPreference("Actor order must contain unique bounded labels.") }
        case let .briefingLength(value):
            guard (100 ... 20_000).contains(value) else {
                throw HistoricalReviewError.invalidPreference("Briefing length must be 100–20,000 words.")
            }
        case let .sectionOrder(values):
            guard !values.isEmpty,
                  values.count <= 3,
                  Set(values).count == values.count,
                  values.allSatisfy(\.isKnown)
            else {
                throw HistoricalReviewError.invalidPreference("Section order must contain unique sections.")
            }
        case let .terminology(values):
            guard !values.isEmpty, values.count <= 256,
                  Set(values.map { HistoricalComparisonEvaluator.normalize($0.sourceTerm) }).count == values.count
            else { throw HistoricalReviewError.invalidPreference("Terminology keys must be unique.") }
        case let .frequentTemplates(values):
            guard !values.isEmpty, values.count <= 256, Set(values).count == values.count else {
                throw HistoricalReviewError.invalidPreference("Template preferences must be unique.")
            }
        case .quotationPolicy, .grouping:
            break
        }
    }

    public var displaySummary: String {
        switch self {
        case let .actorCountryOrder(values): values.joined(separator: ", ")
        case let .briefingLength(value): "Up to \(value) words"
        case let .sectionOrder(values): values.map(\.encodedValue).joined(separator: ", ")
        case let .quotationPolicy(value): value.rawValue
        case let .grouping(value): value.rawValue
        case let .terminology(values): values.map { "\($0.sourceTerm) → \($0.displayTerm)" }.joined(separator: ", ")
        case let .frequentTemplates(values): values.map(\.canonicalString).joined(separator: ", ")
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, strings, integer, sections, quotationPolicy = "quotation_policy", grouping, terminology, templates }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(LearnedPreferenceKind.self, forKey: .kind) {
        case .actorCountryOrder: self = .actorCountryOrder(try container.decode([String].self, forKey: .strings))
        case .briefingLength: self = .briefingLength(try container.decode(UInt32.self, forKey: .integer))
        case .sectionOrder: self = .sectionOrder(try container.decode([BriefingSectionType].self, forKey: .sections))
        case .quotationPolicy: self = .quotationPolicy(try container.decode(LearnedQuotationPolicy.self, forKey: .quotationPolicy))
        case .grouping: self = .grouping(try container.decode(LearnedGrouping.self, forKey: .grouping))
        case .terminology: self = .terminology(try container.decode([TerminologyPreference].self, forKey: .terminology))
        case .frequentTemplates: self = .frequentTemplates(try container.decode([BriefingTemplateID].self, forKey: .templates))
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case let .actorCountryOrder(value): try container.encode(value, forKey: .strings)
        case let .briefingLength(value): try container.encode(value, forKey: .integer)
        case let .sectionOrder(value): try container.encode(value, forKey: .sections)
        case let .quotationPolicy(value): try container.encode(value, forKey: .quotationPolicy)
        case let .grouping(value): try container.encode(value, forKey: .grouping)
        case let .terminology(value): try container.encode(value.sorted(), forKey: .terminology)
        case let .frequentTemplates(value): try container.encode(value.sorted(), forKey: .templates)
        }
    }
}

public struct LearnedPreferenceRecord: Identifiable, Codable, Hashable, Sendable {
    public let preferenceID: LearnedPreferenceID
    public let value: LearnedPreferenceValue
    public let enabled: Bool
    public let version: UInt64
    public let sourceAction: String
    public let createdAt: UTCInstant
    public let updatedAt: UTCInstant

    public var id: String { preferenceID.canonicalString }
    public var kind: LearnedPreferenceKind { value.kind }

    public init(
        preferenceID: LearnedPreferenceID,
        value: LearnedPreferenceValue,
        enabled: Bool,
        version: UInt64,
        sourceAction: String,
        createdAt: UTCInstant,
        updatedAt: UTCInstant
    ) throws {
        try value.validate()
        guard version > 0,
              !sourceAction.isEmpty,
              sourceAction == sourceAction.trimmingCharacters(in: .whitespacesAndNewlines),
              sourceAction.utf8.count <= 128,
              sourceAction.rangeOfCharacter(from: .controlCharacters) == nil,
              updatedAt >= createdAt
        else { throw HistoricalReviewError.invalidPreference("Preference provenance is invalid.") }
        self.preferenceID = preferenceID
        self.value = value
        self.enabled = enabled
        self.version = version
        self.sourceAction = sourceAction
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum LearnedPreferenceEventAction: String, Codable, Hashable, Sendable {
    case created
    case edited
    case enabled
    case disabled
    case removed
    case resetAll = "reset_all"
    case globallyEnabled = "globally_enabled"
    case globallyDisabled = "globally_disabled"
}

public struct LearnedPreferenceEvent: Identifiable, Codable, Hashable, Sendable {
    public let eventID: LearnedPreferenceEventID
    public let action: LearnedPreferenceEventAction
    public let preferenceID: LearnedPreferenceID?
    public let kind: LearnedPreferenceKind?
    public let priorValueDigest: ContentDigest?
    public let replacementValueDigest: ContentDigest?
    public let sourceAction: String
    public let recordedAt: UTCInstant

    public var id: String { eventID.canonicalString }

    public init(
        eventID: LearnedPreferenceEventID,
        action: LearnedPreferenceEventAction,
        preferenceID: LearnedPreferenceID?,
        kind: LearnedPreferenceKind?,
        priorValueDigest: ContentDigest?,
        replacementValueDigest: ContentDigest?,
        sourceAction: String,
        recordedAt: UTCInstant
    ) {
        self.eventID = eventID
        self.action = action
        self.preferenceID = preferenceID
        self.kind = kind
        self.priorValueDigest = priorValueDigest
        self.replacementValueDigest = replacementValueDigest
        self.sourceAction = sourceAction
        self.recordedAt = recordedAt
    }
}

public struct LearnedPreferenceState: Codable, Hashable, Sendable {
    public let globallyEnabled: Bool
    public let settingsVersion: UInt64
    public let preferences: [LearnedPreferenceRecord]
    public let recentEvents: [LearnedPreferenceEvent]

    public init(
        globallyEnabled: Bool,
        settingsVersion: UInt64,
        preferences: [LearnedPreferenceRecord],
        recentEvents: [LearnedPreferenceEvent]
    ) {
        self.globallyEnabled = globallyEnabled
        self.settingsVersion = settingsVersion
        self.preferences = preferences.sorted { $0.preferenceID < $1.preferenceID }
        self.recentEvents = recentEvents.sorted {
            ($0.recordedAt, $0.eventID) > ($1.recordedAt, $1.eventID)
        }
    }
}

public protocol HistoricalReviewRepository: Sendable {
    func historicalIndexStatus() throws -> HistoricalIndexStatus
    func rebuildHistoricalIndex(
        at completedAt: UTCInstant,
        cancellationCheck: @Sendable () throws -> Void
    ) throws -> HistoricalIndexRebuildReport
    func setHistoricalIndexEnabled(_ enabled: Bool, changedAt: UTCInstant) throws
    func searchHistory(_ query: HistoricalSearchQuery) throws -> HistoricalSearchPage
    func publishHistoricalComparison(
        _ comparison: HistoricalComparisonV1,
        expectedCurrentRevisionID: RevisionID?,
        changedAt: UTCInstant
    ) throws
    func learnedPreferenceState(maximumEvents: UInt32) throws -> LearnedPreferenceState
    func saveLearnedPreference(
        preferenceID: LearnedPreferenceID,
        value: LearnedPreferenceValue,
        enabled: Bool,
        sourceAction: String,
        expectedVersion: UInt64?,
        changedAt: UTCInstant
    ) throws -> LearnedPreferenceRecord
    func setLearnedPreferenceEnabled(
        preferenceID: LearnedPreferenceID,
        enabled: Bool,
        sourceAction: String,
        expectedVersion: UInt64,
        changedAt: UTCInstant
    ) throws -> LearnedPreferenceRecord
    func removeLearnedPreference(
        preferenceID: LearnedPreferenceID,
        sourceAction: String,
        expectedVersion: UInt64,
        changedAt: UTCInstant
    ) throws
    func setLearnedPreferencesGloballyEnabled(
        _ enabled: Bool,
        sourceAction: String,
        expectedVersion: UInt64,
        changedAt: UTCInstant
    ) throws -> LearnedPreferenceState
    func resetLearnedPreferences(
        sourceAction: String,
        expectedSettingsVersion: UInt64,
        changedAt: UTCInstant
    ) throws -> LearnedPreferenceState
}

public extension HistoricalReviewRepository {
    func rebuildHistoricalIndex(
        at completedAt: UTCInstant
    ) throws -> HistoricalIndexRebuildReport {
        try rebuildHistoricalIndex(at: completedAt, cancellationCheck: {})
    }
}

public enum HistoricalReviewJobTypes {
    public static let indexRebuild = try! JobType("historical-index-rebuild-v1")
}

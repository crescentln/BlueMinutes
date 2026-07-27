import MeetingBuddyApplication
import MeetingBuddyDomain

struct AnalysisCoveragePresentation:
    Equatable, Sendable
{
    let status: AnalysisLedgerStatus
    let eligibleSegmentCount: Int
    let terminalSegmentCount: Int
    let substantiveSegmentCount: Int
    let nonSubstantiveSegmentCount: Int
    let failedSegmentCount: Int
    let missingSegmentCount: Int

    init(ledger: AnalysisCoverageLedger) {
        status = ledger.status
        let eligible =
            Set(
                ledger
                    .eligibleSegmentRevisions
            )
        let eligibleSegments =
            ledger.segments.filter {
                eligible.contains(
                    $0.segmentRevision
                )
            }
        let recordedRevisions =
            Set(
                eligibleSegments.map(
                    \.segmentRevision
                )
            )
        substantiveSegmentCount =
            eligibleSegments.count {
                $0.disposition
                    == .substantive
            }
        nonSubstantiveSegmentCount =
            eligibleSegments.count {
                $0.disposition
                    == .nonSubstantive
            }
        failedSegmentCount =
            eligibleSegments.count {
                $0.disposition
                    == .failed
            }
        missingSegmentCount =
            eligibleSegments.count {
                $0.disposition
                    == .missing
            }
                + eligible
                .subtracting(
                    recordedRevisions
                )
                .count
        eligibleSegmentCount =
            eligible.count
        terminalSegmentCount =
            substantiveSegmentCount
                + nonSubstantiveSegmentCount
    }

    var isComplete: Bool {
        status == .published
            && terminalSegmentCount
                == eligibleSegmentCount
            && failedSegmentCount == 0
            && missingSegmentCount == 0
    }

    var summary: String {
        if isComplete {
            return
                "\(terminalSegmentCount) / \(eligibleSegmentCount) eligible segments complete"
        }
        return
            "\(terminalSegmentCount) / \(eligibleSegmentCount) terminal results; \(missingSegmentCount) missing; \(failedSegmentCount) failed; ledger incomplete"
    }

    var statusLabel: String {
        switch status {
        case .incomplete:
            "Incomplete"
        case .published:
            "Published"
        }
    }
}

struct AnalysisReviewPresentation: Sendable {
    let positions: [PositionV1]

    private let positionByID: [PositionID: PositionV1]
    private let evidenceByRevision:
        [SemanticRevisionReference: EvidenceRefV1]
    private let representedNameByRevision:
        [SemanticRevisionReference: String]
    private let issueNameByRevision:
        [SemanticRevisionReference: String]
    private let currentPositionRevisionsByLogicalID:
        [String: Set<RevisionID>]

    init(review: AnalysisReviewBundle) {
        positions = review.positions.sorted {
            (
                $0.issueRevision.logicalID.canonicalString,
                $0.representedEntityRevision.logicalID.canonicalString,
                $0.positionID.canonicalString
            ) < (
                $1.issueRevision.logicalID.canonicalString,
                $1.representedEntityRevision.logicalID.canonicalString,
                $1.positionID.canonicalString
            )
        }
        positionByID = Self.uniqueIndex(
            positions,
            key: \.positionID
        )
        evidenceByRevision = Self.uniqueCurrentSemanticIndex(
            review.evidence,
            logicalID: \.evidenceID
        )

        var representedNames: [SemanticRevisionReference: String] = [:]
        var ambiguousRepresentedEntities: Set<SemanticRevisionReference> = []
        Self.insertNames(
            review.participants,
            logicalID: \.participantID,
            name: \.displayName,
            into: &representedNames,
            ambiguous: &ambiguousRepresentedEntities
        )
        Self.insertNames(
            review.organizations,
            logicalID: \.organizationID,
            name: \.displayName,
            into: &representedNames,
            ambiguous: &ambiguousRepresentedEntities
        )
        representedNameByRevision = representedNames

        issueNameByRevision = Self.uniqueNamedSemanticIndex(
            review.issues,
            logicalID: \.issueID,
            name: { $0.title.text }
        )

        currentPositionRevisionsByLogicalID = Dictionary(
            grouping: positions,
            by: { $0.positionID.canonicalString }
        ).mapValues {
            Set($0.map(\.revision.revisionID))
        }
    }

    func position(id: PositionID?) -> PositionV1? {
        guard let id else { return nil }
        return positionByID[id]
    }

    func representedName(
        for reference: SemanticRevisionReference
    ) -> String? {
        representedNameByRevision[reference]
    }

    func issueName(
        for reference: SemanticRevisionReference
    ) -> String? {
        issueNameByRevision[reference]
    }

    func evidence(
        for claim: EvidenceLinkedClaim
    ) -> [EvidenceRefV1] {
        Array(Set(claim.evidenceRevisions))
            .sorted()
            .compactMap { evidenceByRevision[$0] }
    }

    func evidence(
        for reference: SemanticRevisionReference
    ) -> EvidenceRefV1? {
        evidenceByRevision[reference]
    }

    func unresolvedEvidenceCount(
        for claim: EvidenceLinkedClaim
    ) -> Int {
        Set(claim.evidenceRevisions).filter {
            evidenceByRevision[$0] == nil
        }.count
    }

    func isStale(
        _ card: DelegationPositionCardV1
    ) -> Bool {
        card.positionRevisions.contains { reference in
            guard let current =
                currentPositionRevisionsByLogicalID[
                    reference.logicalID.canonicalString
                ]
            else {
                return true
            }
            return current.count != 1
                || !current.contains(reference.revisionID)
        }
    }

    private static func uniqueIndex<Value, Key: Hashable>(
        _ values: [Value],
        key: KeyPath<Value, Key>
    ) -> [Key: Value] {
        var result: [Key: Value] = [:]
        var ambiguous: Set<Key> = []
        for value in values {
            let valueKey = value[keyPath: key]
            if result[valueKey] != nil {
                result.removeValue(forKey: valueKey)
                ambiguous.insert(valueKey)
            } else if !ambiguous.contains(valueKey) {
                result[valueKey] = value
            }
        }
        return result
    }

    private static func uniqueCurrentSemanticIndex<
        Value: SemanticRevisionContract,
        Tag: LogicalObjectIDScope
    >(
        _ values: [Value],
        logicalID: KeyPath<Value, StableID<Tag>>
    ) -> [SemanticRevisionReference: Value] {
        var result: [SemanticRevisionReference: Value] = [:]
        var referenceByLogicalID:
            [StableID<Tag>: SemanticRevisionReference] = [:]
        var ambiguousLogicalIDs: Set<StableID<Tag>> = []
        for value in values {
            let valueLogicalID = value[keyPath: logicalID]
            guard !ambiguousLogicalIDs.contains(
                valueLogicalID
            ) else {
                continue
            }
            guard let reference = semanticReference(
                logicalID: valueLogicalID,
                revisionID: value.revision.revisionID
            ) else {
                continue
            }
            if let priorReference =
                referenceByLogicalID[valueLogicalID]
            {
                result.removeValue(forKey: priorReference)
                referenceByLogicalID.removeValue(
                    forKey: valueLogicalID
                )
                ambiguousLogicalIDs.insert(valueLogicalID)
                continue
            }
            referenceByLogicalID[valueLogicalID] = reference
            result[reference] = value
        }
        return result
    }

    private static func uniqueNamedSemanticIndex<
        Value: SemanticRevisionContract,
        Tag: LogicalObjectIDScope
    >(
        _ values: [Value],
        logicalID: KeyPath<Value, StableID<Tag>>,
        name: (Value) -> String
    ) -> [SemanticRevisionReference: String] {
        var result: [SemanticRevisionReference: String] = [:]
        var ambiguous: Set<SemanticRevisionReference> = []
        insertNames(
            values,
            logicalID: logicalID,
            name: name,
            into: &result,
            ambiguous: &ambiguous
        )
        return result
    }

    private static func insertNames<
        Value: SemanticRevisionContract,
        Tag: LogicalObjectIDScope
    >(
        _ values: [Value],
        logicalID: KeyPath<Value, StableID<Tag>>,
        name: (Value) -> String,
        into result: inout [SemanticRevisionReference: String],
        ambiguous: inout Set<SemanticRevisionReference>
    ) {
        for value in values {
            guard let reference = semanticReference(
                logicalID: value[keyPath: logicalID],
                revisionID: value.revision.revisionID
            ) else {
                continue
            }
            if result[reference] != nil {
                result.removeValue(forKey: reference)
                ambiguous.insert(reference)
            } else if !ambiguous.contains(reference) {
                result[reference] = name(value)
            }
        }
    }

    private static func semanticReference<
        Tag: LogicalObjectIDScope
    >(
        logicalID: StableID<Tag>,
        revisionID: RevisionID
    ) -> SemanticRevisionReference? {
        try? SemanticRevisionReference(
            logicalID: logicalID,
            revisionID: revisionID
        )
    }
}

struct AnalysisReviewPresentationCacheKey:
    Hashable, Sendable
{
    let ledgerID: AnalysisCoverageLedgerID
    let semanticRevisions: [SemanticRevisionReference]

    init(review: AnalysisReviewBundle) {
        ledgerID = review.ledger.ledgerID
        semanticRevisions = (
            Self.references(review.evidence, logicalID: \.evidenceID)
                + Self.references(
                    review.participants,
                    logicalID: \.participantID
                )
                + Self.references(
                    review.organizations,
                    logicalID: \.organizationID
                )
                + Self.references(review.issues, logicalID: \.issueID)
                + Self.references(
                    review.positions,
                    logicalID: \.positionID
                )
                + Self.references(
                    review.interventionCards,
                    logicalID: \.interventionID
                )
                + Self.references(
                    review.delegationPositionCards,
                    logicalID: \.cardID
                )
        ).sorted()
    }

    private static func references<
        Value: SemanticRevisionContract,
        Tag: LogicalObjectIDScope
    >(
        _ values: [Value],
        logicalID: KeyPath<Value, StableID<Tag>>
    ) -> [SemanticRevisionReference] {
        values.compactMap {
            try? SemanticRevisionReference(
                logicalID: $0[keyPath: logicalID],
                revisionID: $0.revision.revisionID
            )
        }
    }
}

struct AnalysisReviewPresentationCache: Sendable {
    let key: AnalysisReviewPresentationCacheKey
    let presentation: AnalysisReviewPresentation

    init(review: AnalysisReviewBundle) {
        key = AnalysisReviewPresentationCacheKey(review: review)
        presentation = AnalysisReviewPresentation(review: review)
    }
}

struct AnalysisEvidenceSelection: Hashable, Sendable {
    let context: String
    let claim: EvidenceLinkedClaim
    let evidenceReference: SemanticRevisionReference
}

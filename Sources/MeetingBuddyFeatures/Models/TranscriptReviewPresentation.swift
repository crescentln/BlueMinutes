import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

enum TranscriptOutlineScope:
    String,
    CaseIterable,
    Identifiable,
    Sendable
{
    case all
    case needsReview = "needs_review"
    case speakerReview = "speaker_review"
    case humanEdited = "human_edited"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            "All Segments"
        case .needsReview:
            "Needs Review"
        case .speakerReview:
            "Speaker Review"
        case .humanEdited:
            "Human Edited"
        }
    }
}

struct TranscriptOutlineAnchor:
    Hashable,
    Identifiable,
    Sendable
{
    let segmentID: TranscriptSegmentID
    let startMilliseconds: Int64

    var id: TranscriptSegmentID {
        segmentID
    }

    var label: String {
        let totalSeconds =
            max(startMilliseconds, 0) / 1_000
        let hours = totalSeconds / 3_600
        let minutes =
            (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(
                format:
                    "%02lld:%02lld:%02lld",
                hours,
                minutes,
                seconds
            )
        }
        return String(
            format:
                "%02lld:%02lld",
            minutes,
            seconds
        )
    }
}

struct TranscriptNavigationIndex: Sendable {
    let orderedSegmentIDs: [TranscriptSegmentID]
    private let positionBySegmentID: [TranscriptSegmentID: Int]

    init(orderedSegmentIDs: [TranscriptSegmentID]) {
        self.orderedSegmentIDs = orderedSegmentIDs
        var positions: [TranscriptSegmentID: Int] = [:]
        var ambiguousIDs: Set<TranscriptSegmentID> = []
        for (position, segmentID) in
            orderedSegmentIDs.enumerated()
        {
            if positions[segmentID] != nil {
                positions.removeValue(forKey: segmentID)
                ambiguousIDs.insert(segmentID)
            } else if !ambiguousIDs.contains(segmentID) {
                positions[segmentID] = position
            }
        }
        positionBySegmentID = positions
    }

    func previous(
        to segmentID: TranscriptSegmentID?
    ) -> TranscriptSegmentID? {
        guard let segmentID,
              let position = positionBySegmentID[segmentID],
              position > orderedSegmentIDs.startIndex
        else {
            return nil
        }
        return orderedSegmentIDs[position - 1]
    }

    func next(
        to segmentID: TranscriptSegmentID?
    ) -> TranscriptSegmentID? {
        guard let segmentID,
              let position = positionBySegmentID[segmentID],
              position + 1 < orderedSegmentIDs.endIndex
        else {
            return nil
        }
        return orderedSegmentIDs[position + 1]
    }
}

struct TranscriptReviewPresentation: Sendable {
    static let maximumSearchQueryUTF8Bytes =
        512
    static let outlineIntervalMilliseconds:
        Int64 = 5 * 60 * 1_000

    let segments: [TranscriptSegmentV1]
    let navigation: TranscriptNavigationIndex
    let outlineAnchors:
        [TranscriptOutlineAnchor]
    let uncertainSpeakerCount: Int
    let noSpeechChunks: [TranscriptChunkCoverage]
    let verifiedNoSpeechChunkCount: Int
    let unresolvedNoSpeechChunkCount: Int

    private let segmentByID: [TranscriptSegmentID: TranscriptSegmentV1]
    private let translationBySourceRevision:
        [SemanticRevisionReference: TranslationSegmentV1]
    private let assignmentsByTranscriptRevision:
        [SemanticRevisionReference: [SpeakerAssignmentV1]]
    private let evidenceByRevision:
        [SemanticRevisionReference: EvidenceRefV1]
    private let coverageByReviewedRevision:
        [SemanticRevisionReference: [TranscriptChunkCoverage]]
    private let normalizedSearchTextBySegmentID:
        [TranscriptSegmentID: String]

    init(review: TranscriptReviewBundle) {
        let orderedSegments = review.transcriptSegments.sorted {
            (
                $0.timeRange.startMilliseconds,
                $0.segmentID.canonicalString
            ) < (
                $1.timeRange.startMilliseconds,
                $1.segmentID.canonicalString
            )
        }
        segments = orderedSegments
        navigation = TranscriptNavigationIndex(
            orderedSegmentIDs: orderedSegments.map(\.segmentID)
        )
        var anchors:
            [TranscriptOutlineAnchor] = []
        var lastBucket: Int64?
        for segment in orderedSegments {
            let bucket =
                segment.timeRange
                .startMilliseconds
                / Self.outlineIntervalMilliseconds
            if bucket != lastBucket {
                anchors.append(
                    TranscriptOutlineAnchor(
                        segmentID:
                            segment.segmentID,
                        startMilliseconds:
                            segment.timeRange
                            .startMilliseconds
                    )
                )
                lastBucket = bucket
            }
        }
        outlineAnchors = anchors
        var segmentsByID:
            [TranscriptSegmentID: TranscriptSegmentV1] = [:]
        var ambiguousSegmentIDs: Set<TranscriptSegmentID> = []
        for segment in orderedSegments {
            if segmentsByID[segment.segmentID] != nil {
                segmentsByID.removeValue(
                    forKey: segment.segmentID
                )
                ambiguousSegmentIDs.insert(segment.segmentID)
            } else if !ambiguousSegmentIDs.contains(
                segment.segmentID
            ) {
                segmentsByID[segment.segmentID] = segment
            }
        }
        segmentByID = segmentsByID

        var translations:
            [SemanticRevisionReference: TranslationSegmentV1] = [:]
        var ambiguousTranslationSources:
            Set<SemanticRevisionReference> = []
        for translation in review.translations.sorted(by: {
            $0.revision.revisionID.canonicalString
                < $1.revision.revisionID.canonicalString
        }) {
            let reference = translation.sourceSegmentRevision
            if translations[reference] != nil {
                translations.removeValue(forKey: reference)
                ambiguousTranslationSources.insert(reference)
            } else if !ambiguousTranslationSources.contains(reference) {
                translations[reference] = translation
            }
        }
        translationBySourceRevision = translations

        var assignments:
            [SemanticRevisionReference: [SpeakerAssignmentV1]] = [:]
        let orderedAssignments = review.speakerAssignments.sorted {
            (
                $0.revision.createdAt,
                $0.revision.revisionID.canonicalString
            ) < (
                $1.revision.createdAt,
                $1.revision.revisionID.canonicalString
            )
        }
        for assignment in orderedAssignments {
            for reference in assignment.transcriptSegmentRevisions {
                assignments[reference, default: []]
                    .append(assignment)
            }
        }
        assignmentsByTranscriptRevision = assignments

        var evidence:
            [SemanticRevisionReference: EvidenceRefV1] = [:]
        var ambiguousEvidenceReferences:
            Set<SemanticRevisionReference> = []
        for item in review.evidenceRefs {
            guard let reference = Self.reference(
                logicalID: item.evidenceID,
                revisionID: item.revision.revisionID
            ) else { continue }
            if evidence[reference] != nil {
                evidence.removeValue(forKey: reference)
                ambiguousEvidenceReferences.insert(reference)
            } else if !ambiguousEvidenceReferences.contains(reference) {
                evidence[reference] = item
            }
        }
        evidenceByRevision = evidence

        var coverage:
            [SemanticRevisionReference: [TranscriptChunkCoverage]] = [:]
        for chunk in review.manifest.chunks {
            if let reference = chunk.reviewedSegmentRevision {
                coverage[reference, default: []].append(chunk)
            }
        }
        coverageByReviewedRevision = coverage
        noSpeechChunks = review.manifest.chunks.filter {
            $0.disposition == .noSpeech
        }.sorted()
        verifiedNoSpeechChunkCount = noSpeechChunks.filter {
            guard let confirmation = $0.noSpeechConfirmation else {
                return false
            }
            return confirmation.method == .exactDigitalSilence
                && confirmation.verifiedCoreRange == $0.coreRange
                && confirmation.verifierVersion
                    == TranscriptNoSpeechConfirmation.verifierVersion
        }.count
        unresolvedNoSpeechChunkCount =
            noSpeechChunks.count - verifiedNoSpeechChunkCount
        uncertainSpeakerCount = orderedSegments.filter { segment in
            guard let reference = Self.reference(for: segment) else {
                return true
            }
            return !(assignments[reference] ?? [])
                .contains(where: Self.isConfirmedAssignment)
        }.count
        var searchableText:
            [TranscriptSegmentID: String] = [:]
        searchableText.reserveCapacity(
            orderedSegments.count
        )
        for segment in orderedSegments {
            let reference =
                Self.reference(for: segment)
            let translation =
                reference.flatMap {
                    translations[$0]
                }
            let values = [
                segment.text,
                translation?.translatedText,
                segment.detectedLanguage.value,
                segment.reviewStatus.encodedValue,
                segment.speechSourceKind
                    .encodedValue,
                segment.revision.createdBy
                    .encodedValue,
                String(
                    segment.timeRange
                        .startMilliseconds
                        / 1_000
                ),
            ]
                .compactMap { $0 }
                .joined(separator: "\n")
            searchableText[segment.segmentID] =
                Self.normalizeSearchText(
                    values
                )
        }
        normalizedSearchTextBySegmentID =
            searchableText
    }

    func segment(
        id: TranscriptSegmentID?
    ) -> TranscriptSegmentV1? {
        guard let id else { return nil }
        return segmentByID[id]
    }

    func translation(
        for segment: TranscriptSegmentV1
    ) -> TranslationSegmentV1? {
        guard let reference = Self.reference(for: segment) else {
            return nil
        }
        return translationBySourceRevision[reference]
    }

    func assignments(
        for segment: TranscriptSegmentV1
    ) -> [SpeakerAssignmentV1] {
        guard let reference = Self.reference(for: segment) else {
            return []
        }
        return assignmentsByTranscriptRevision[reference] ?? []
    }

    func hasConfirmedSpeaker(
        for segment: TranscriptSegmentV1
    ) -> Bool {
        assignments(for: segment).contains(
            where: Self.isConfirmedAssignment
        )
    }

    func evidence(
        for segment: TranscriptSegmentV1
    ) -> [EvidenceRefV1] {
        let references = Array(
            Set(
                assignments(for: segment)
                    .flatMap(\.evidenceRevisions)
            )
        ).sorted()
        return references.compactMap {
            evidenceByRevision[$0]
        }
    }

    func unresolvedEvidenceCount(
        for segment: TranscriptSegmentV1
    ) -> Int {
        let references = Set(
            assignments(for: segment)
                .flatMap(\.evidenceRevisions)
        )
        return references.filter {
            evidenceByRevision[$0] == nil
        }.count
    }

    func coverage(
        for segment: TranscriptSegmentV1
    ) -> [TranscriptChunkCoverage] {
        guard let reference = Self.reference(for: segment) else {
            return []
        }
        return coverageByReviewedRevision[reference] ?? []
    }

    func segments(
        matching query: String,
        scope: TranscriptOutlineScope
    ) -> [TranscriptSegmentV1] {
        guard query.utf8.count
                <= Self.maximumSearchQueryUTF8Bytes
        else {
            return []
        }
        let normalizedQuery =
            Self.normalizeSearchText(
                query.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            )
        let tokens = normalizedQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        return segments.filter { segment in
            guard matchesScope(
                scope,
                segment: segment
            ) else {
                return false
            }
            guard !tokens.isEmpty else {
                return true
            }
            guard let searchable =
                    normalizedSearchTextBySegmentID[
                        segment.segmentID
                    ]
            else {
                return false
            }
            return tokens.allSatisfy {
                searchable.contains($0)
            }
        }
    }

    private func matchesScope(
        _ scope: TranscriptOutlineScope,
        segment: TranscriptSegmentV1
    ) -> Bool {
        switch scope {
        case .all:
            true
        case .needsReview:
            segment.reviewStatus
                == .needsReview
        case .speakerReview:
            !hasConfirmedSpeaker(
                for: segment
            )
        case .humanEdited:
            segment.revision.createdBy
                == .user
        }
    }

    private static func normalizeSearchText(
        _ text: String
    ) -> String {
        text.folding(
            options: [
                .caseInsensitive,
                .diacriticInsensitive,
                .widthInsensitive,
            ],
            locale:
                Locale(
                    identifier:
                        "en_US_POSIX"
                )
        )
    }

    private static func reference(
        for segment: TranscriptSegmentV1
    ) -> SemanticRevisionReference? {
        reference(
            logicalID: segment.segmentID,
            revisionID: segment.revision.revisionID
        )
    }

    private static func reference<Tag: LogicalObjectIDScope>(
        logicalID: StableID<Tag>,
        revisionID: RevisionID
    ) -> SemanticRevisionReference? {
        try? SemanticRevisionReference(
            logicalID: logicalID,
            revisionID: revisionID
        )
    }

    private static func isConfirmedAssignment(
        _ assignment: SpeakerAssignmentV1
    ) -> Bool {
        assignment.certainty == .confirmed
            && assignment.reviewStatus == .confirmed
            && assignment.userConfirmed
    }
}

struct TranscriptReviewPresentationCacheKey:
    Hashable, Sendable
{
    let manifestID: TranscriptCoverageManifestID
    let speakerAssignmentRevisions: [SemanticRevisionReference]
    let evidenceRevisions: [SemanticRevisionReference]

    init(review: TranscriptReviewBundle) {
        manifestID = review.manifest.manifestID
        speakerAssignmentRevisions = review.speakerAssignments
            .compactMap {
                try? SemanticRevisionReference(
                    logicalID: $0.assignmentID,
                    revisionID: $0.revision.revisionID
                )
            }
            .sorted()
        evidenceRevisions = review.evidenceRefs
            .compactMap {
                try? SemanticRevisionReference(
                    logicalID: $0.evidenceID,
                    revisionID: $0.revision.revisionID
                )
            }
            .sorted()
    }
}

struct TranscriptReviewPresentationCache: Sendable {
    let key: TranscriptReviewPresentationCacheKey
    let presentation: TranscriptReviewPresentation

    init(review: TranscriptReviewBundle) {
        key = TranscriptReviewPresentationCacheKey(review: review)
        presentation = TranscriptReviewPresentation(review: review)
    }
}

enum TranscriptCommandAvailability {
    static func canNavigate(
        hasDestination: Bool,
        isWorking: Bool,
        isInteractionLocked: Bool,
        isConfirmationPresented: Bool
    ) -> Bool {
        hasDestination
            && !isWorking
            && !isInteractionLocked
            && !isConfirmationPresented
    }

    static func canSave(
        hasSavableDraft: Bool,
        isWorking: Bool,
        isInteractionLocked: Bool,
        isConfirmationPresented: Bool
    ) -> Bool {
        hasSavableDraft
            && !isWorking
            && !isInteractionLocked
            && !isConfirmationPresented
    }
}

enum TranscriptEditorFocus: Hashable, Sendable {
    case transcript
    case translation
    case speaker
}

enum TranscriptEvidenceInspectorSelection {
    static func resolve(
        requestedRevisionID: RevisionID?,
        availableRevisionIDs: [RevisionID]
    ) -> RevisionID? {
        guard let requestedRevisionID,
              availableRevisionIDs.contains(
                  requestedRevisionID
              )
        else {
            return nil
        }
        return requestedRevisionID
    }
}

enum TranscriptDraftKind: Hashable, Sendable {
    case transcript
    case translation
    case speaker
}

enum TranscriptDraftSaveResolution {
    static func resolve(
        focusedEditor: TranscriptEditorFocus?,
        transcriptIsDirty: Bool,
        translationIsDirty: Bool,
        speakerIsDirty: Bool
    ) -> TranscriptDraftKind? {
        if let focusedEditor {
            switch focusedEditor {
            case .transcript:
                return transcriptIsDirty ? .transcript : nil
            case .translation:
                return translationIsDirty ? .translation : nil
            case .speaker:
                return speakerIsDirty ? .speaker : nil
            }
        }

        let dirtyDrafts: [TranscriptDraftKind] = [
            transcriptIsDirty ? .transcript : nil,
            translationIsDirty ? .translation : nil,
            speakerIsDirty ? .speaker : nil
        ].compactMap { $0 }
        return dirtyDrafts.count == 1 ? dirtyDrafts[0] : nil
    }
}

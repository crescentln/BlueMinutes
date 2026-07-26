import MeetingBuddyApplication
import MeetingBuddyDomain

struct TranscriptNavigationIndex: Sendable {
    let orderedSegmentIDs: [TranscriptSegmentID]
    private let positionBySegmentID: [TranscriptSegmentID: Int]

    init(orderedSegmentIDs: [TranscriptSegmentID]) {
        self.orderedSegmentIDs = orderedSegmentIDs
        positionBySegmentID = Dictionary(
            uniqueKeysWithValues:
                orderedSegmentIDs.enumerated().map {
                    ($0.element, $0.offset)
                }
        )
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
    let segments: [TranscriptSegmentV1]
    let navigation: TranscriptNavigationIndex
    let uncertainSpeakerCount: Int
    let noSpeechChunkCount: Int

    private let segmentByID: [TranscriptSegmentID: TranscriptSegmentV1]
    private let translationBySourceRevision:
        [RevisionID: TranslationSegmentV1]
    private let assignmentsByTranscriptRevision:
        [RevisionID: [SpeakerAssignmentV1]]
    private let evidenceByRevision: [RevisionID: EvidenceRefV1]
    private let coverageByReviewedRevision:
        [RevisionID: [TranscriptChunkCoverage]]

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
        segmentByID = Dictionary(
            uniqueKeysWithValues:
                orderedSegments.map { ($0.segmentID, $0) }
        )

        var translations: [RevisionID: TranslationSegmentV1] = [:]
        for translation in review.translations.sorted(by: {
            $0.revision.revisionID.canonicalString
                < $1.revision.revisionID.canonicalString
        }) {
            translations[
                translation.sourceSegmentRevision.revisionID,
                default: translation
            ] = translation
        }
        translationBySourceRevision = translations

        var assignments: [RevisionID: [SpeakerAssignmentV1]] = [:]
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
                assignments[reference.revisionID, default: []]
                    .append(assignment)
            }
        }
        assignmentsByTranscriptRevision = assignments

        evidenceByRevision = Dictionary(
            uniqueKeysWithValues:
                review.evidenceRefs.map {
                    ($0.revision.revisionID, $0)
                }
        )

        var coverage: [RevisionID: [TranscriptChunkCoverage]] = [:]
        for chunk in review.manifest.chunks {
            if let reference = chunk.reviewedSegmentRevision {
                coverage[reference.revisionID, default: []].append(chunk)
            }
        }
        coverageByReviewedRevision = coverage
        noSpeechChunkCount = review.manifest.chunks.filter {
            $0.disposition == .noSpeech
        }.count
        uncertainSpeakerCount = orderedSegments.filter { segment in
            !(assignments[segment.revision.revisionID] ?? [])
                .contains(where: Self.isConfirmedAssignment)
        }.count
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
        translationBySourceRevision[segment.revision.revisionID]
    }

    func assignments(
        for segment: TranscriptSegmentV1
    ) -> [SpeakerAssignmentV1] {
        assignmentsByTranscriptRevision[
            segment.revision.revisionID
        ] ?? []
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
            evidenceByRevision[$0.revisionID]
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
            evidenceByRevision[$0.revisionID] == nil
        }.count
    }

    func coverage(
        for segment: TranscriptSegmentV1
    ) -> [TranscriptChunkCoverage] {
        coverageByReviewedRevision[
            segment.revision.revisionID
        ] ?? []
    }

    private static func isConfirmedAssignment(
        _ assignment: SpeakerAssignmentV1
    ) -> Bool {
        assignment.certainty == .confirmed
            && assignment.reviewStatus == .confirmed
            && assignment.userConfirmed
    }
}

enum TranscriptEditorFocus: Hashable, Sendable {
    case transcript
    case translation
    case speaker
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

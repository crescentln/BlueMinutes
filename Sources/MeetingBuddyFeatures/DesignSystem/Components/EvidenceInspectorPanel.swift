import MeetingBuddyApplication
import MeetingBuddyDomain
import SwiftUI

struct EvidenceInspectorPanel: View {
    let segment: TranscriptSegmentV1?
    let coverage: [TranscriptChunkCoverage]
    let evidence: [EvidenceRefV1]
    let unresolvedEvidenceCount: Int

    var body: some View {
        Group {
            if let segment {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("Evidence Inspector")
                            .font(.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        sourceSection(segment)
                        coverageSection
                        evidenceSection
                    }
                    .padding(18)
                }
            } else {
                ContentUnavailableView(
                    "Select a Transcript Segment",
                    systemImage: "link.circle",
                    description: Text(
                        "The inspector shows exact source and EvidenceRef revisions for the selected segment."
                    )
                )
            }
        }
        .accessibilityIdentifier(
            "BlueMinutes.Transcript.EvidenceInspector"
        )
    }

    private func sourceSection(
        _ segment: TranscriptSegmentV1
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorialSectionHeader(
                "Source and provenance",
                detail:
                    "These fields come from the selected immutable TranscriptSegment revision."
            )
            LabeledContent(
                "Time",
                value: timeLabel(segment.timeRange)
            )
            LabeledContent(
                "Speech source",
                value: label(segment.speechSourceKind.encodedValue)
            )
            LabeledContent(
                "Source asset",
                value: shortRevision(
                    segment.sourceAssetRevision.revisionID
                )
            )
            LabeledContent(
                "Transcript revision",
                value: shortRevision(segment.revision.revisionID)
            )
            LabeledContent(
                "Created by",
                value: label(segment.revision.createdBy.encodedValue)
            )
            LabeledContent(
                "Classification",
                value: label(
                    segment.revision.dataClassification.encodedValue
                )
            )
            LabeledContent(
                "Confidence",
                value: confidenceLabel(segment.confidence)
            )
            LabeledContent(
                "Review status",
                value: label(segment.reviewStatus.encodedValue)
            )
            LabeledContent(
                "Human confirmed",
                value: segment.userConfirmed ? "Yes" : "No"
            )
            if let superseded = segment.revision.supersedesRevisionID {
                LabeledContent(
                    "Supersedes",
                    value: shortRevision(superseded)
                )
            }
        }
    }

    private var coverageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorialSectionHeader(
                "Coverage ownership",
                detail:
                    "The selected revision may own one or more deterministic core chunks."
            )
            if coverage.isEmpty {
                WorkflowStateView(
                    title: "Coverage mapping unavailable",
                    detail:
                        "No reviewed core chunk resolves to this revision. The review cannot infer ownership.",
                    systemImage: "exclamationmark.triangle",
                    tone: .failure
                )
            } else {
                LabeledContent(
                    "Owned core chunks",
                    value: String(coverage.count)
                )
                LabeledContent(
                    "Chunk indexes",
                    value:
                        coverage.map { String($0.index) }
                        .joined(separator: ", ")
                )
                LabeledContent(
                    "Disposition",
                    value:
                        Array(Set(coverage.map(\.disposition.rawValue)))
                        .sorted()
                        .map(label)
                        .joined(separator: ", ")
                )
            }
        }
    }

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorialSectionHeader(
                "Exact evidence references",
                detail:
                    "Only persisted EvidenceRef.v1 objects referenced by the selected segment's speaker assignments appear here."
            )
            if unresolvedEvidenceCount > 0 {
                WorkflowStateView(
                    title: "Evidence resolution failed closed",
                    detail:
                        "\(unresolvedEvidenceCount) referenced evidence revision(s) could not be resolved and are not represented as evidence.",
                    systemImage: "exclamationmark.triangle",
                    tone: .failure
                )
            }
            if evidence.isEmpty {
                WorkflowStateView(
                    title: "No typed speaker evidence",
                    detail:
                        "The selected segment has no resolved EvidenceRef.v1 through its current speaker assignments.",
                    systemImage: "link.badge.plus",
                    tone: .neutral
                )
            } else {
                ForEach(
                    evidence,
                    id: \.revision.revisionID
                ) { item in
                    evidenceItem(item)
                    if item.revision.revisionID
                        != evidence.last?.revision.revisionID
                    {
                        Divider()
                    }
                }
            }
        }
    }

    private func evidenceItem(
        _ item: EvidenceRefV1
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            EvidenceBadge(
                title: label(item.evidenceKind.rawValue),
                systemImage: "link.circle"
            )
            LabeledContent(
                "Evidence revision",
                value: shortRevision(item.revision.revisionID)
            )
            LabeledContent(
                "Exact source",
                value:
                    "\(label(item.source.objectType.encodedValue)) · \(shortRevision(item.source.revisionID))"
            )
            LabeledContent(
                "Locator",
                value: locationLabel(item.location)
            )
            LabeledContent(
                "Confidence",
                value: confidenceLabel(item.confidence)
            )
            LabeledContent(
                "Excerpt language",
                value: item.excerpt.language.value
            )
            LabeledContent(
                "Translation status",
                value: label(
                    item.excerpt.translationStatus.encodedValue
                )
            )
            Text(item.excerpt.text)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Evidence excerpt")
        }
    }

    private func locationLabel(
        _ location: EvidenceLocation
    ) -> String {
        switch location {
        case let .transcriptSegment(_, textRange):
            return textRange.map(textRangeLabel)
                .map { "Transcript segment · \($0)" }
                ?? "Whole transcript segment"
        case let .documentLocation(_, location):
            return documentLocationLabel(location)
        case let .mediaTimeRange(_, range):
            return "Media \(timeLabel(range))"
        case let .userConfirmedNote(_, textRange):
            return textRange.map(textRangeLabel)
                .map { "User-confirmed note · \($0)" }
                ?? "Whole user-confirmed note"
        case let .meetingMetadata(_, field):
            return "Meeting metadata · \(field)"
        case let .semanticObjectRevision(_, jsonPointer):
            return jsonPointer.map {
                "Semantic object · JSON pointer \($0)"
            } ?? "Whole semantic object revision"
        case let .officialStatement(_, location):
            return "Official statement · \(documentLocationLabel(location))"
        }
    }

    private func documentLocationLabel(
        _ location: DocumentLocation
    ) -> String {
        var parts: [String] = []
        if let page = location.pageNumber {
            parts.append("page \(page)")
        }
        if let paragraph = location.paragraphNumber {
            parts.append("paragraph \(paragraph)")
        }
        if let section = location.section {
            parts.append("section \(section)")
        }
        if let range = location.textRange {
            parts.append(textRangeLabel(range))
        }
        return parts.joined(separator: " · ")
    }

    private func textRangeLabel(_ range: UTF8TextRange) -> String {
        "UTF-8 bytes \(range.startOffset)..<\(range.startOffset + range.length)"
    }

    private func timeLabel(_ range: MediaTimeRange) -> String {
        let start = Double(range.startMilliseconds) / 1_000
        let end = Double(range.endMilliseconds) / 1_000
        return
            "\(start.formatted(.number.precision(.fractionLength(1))))–\(end.formatted(.number.precision(.fractionLength(1)))) s"
    }

    private func confidenceLabel(
        _ confidence: ConfidenceScore
    ) -> String {
        let percent = Double(confidence.millionths) / 10_000
        return percent.formatted(
            .number.precision(.fractionLength(1))
        ) + "%"
    }

    private func shortRevision(_ revisionID: RevisionID) -> String {
        String(revisionID.canonicalString.prefix(12)) + "…"
    }

    private func label(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

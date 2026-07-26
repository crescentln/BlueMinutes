import MeetingBuddyApplication
import MeetingBuddyDomain
import SwiftUI

struct BriefingEditorialCanvas: View {
    let review: BriefingReviewBundle
    let sections: [BriefingSectionV1]
    let selectSection: @MainActor (
        BriefingSectionType
    ) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 28) {
            documentHeader

            ForEach(
                sections,
                id: \.revision.revisionID
            ) { section in
                dossierSection(section)
                if section.sectionType
                    != sections.last?.sectionType
                {
                    Divider()
                }
            }
        }
        .padding(30)
        .background(
            BlueMinutesColors.canvas,
            in: RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
            .stroke(.separator.opacity(0.55))
        }
        .accessibilityIdentifier(
            "BlueMinutes.Briefing.EditorialCanvas"
        )
    }

    private var documentHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                review.publication.finalBriefing
                    .documentTitle
            )
            .font(.largeTitle.weight(.semibold))
            .fixedSize(
                horizontal: false,
                vertical: true
            )
            .accessibilityAddTraits(.isHeader)
            Text("Editorial Briefing Canvas")
                .font(.headline)
                .foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    publicationBadges
                }
                VStack(
                    alignment: .leading,
                    spacing: 6
                ) {
                    publicationBadges
                }
            }
        }
    }

    @ViewBuilder
    private var publicationBadges: some View {
        EvidenceBadge(
            title: "3 contract sections",
            systemImage: "doc.on.doc"
        )
        EvidenceBadge(
            title:
                review.publication.validationReport
                    .passed
                ? "Validation passed"
                : "Validation blocked",
            systemImage: "checkmark.seal"
        )
        EvidenceBadge(
            title:
                review.isHumanConfirmed
                ? "Human confirmed"
                : "Confirmation incomplete",
            systemImage:
                "person.crop.circle.badge.checkmark"
        )
    }

    private func dossierSection(
        _ section: BriefingSectionV1
    ) -> some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                EditorialSectionHeader(
                    section.title,
                    detail:
                        "\(sectionStatus(section)) · revision \(short(section.revision.revisionID.canonicalString))"
                )
                Spacer()
                Button("Edit \(section.title)") {
                    selectSection(section.sectionType)
                }
                .buttonStyle(.link)
            }

            ForEach(
                Array(section.metadata.enumerated()),
                id: \.offset
            ) { _, entry in
                LabeledContent(
                    entry.label,
                    value: entry.value
                )
            }

            ForEach(section.items, id: \.itemID) {
                item in
                briefingItem(item)
            }

            LabeledContent(
                "Published section provenance",
                value: label(
                    section.revision.createdBy
                        .encodedValue
                )
            )
            .font(.caption)
            LabeledContent(
                "Published section human confirmation",
                value:
                    section.userConfirmed
                    ? "Confirmed"
                    : "Not confirmed"
            )
            .font(.caption)
        }
    }

    private func briefingItem(
        _ item: BriefingSectionItem
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let itemLabel = item.label {
                Text(itemLabel)
                    .font(.headline)
            }
            Text(item.claim.text)
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    claimBadges(item.claim)
                }
                VStack(
                    alignment: .leading,
                    spacing: 6
                ) {
                    claimBadges(item.claim)
                }
            }

            exactEvidenceReferences(item.claim)
            exactSourceReferences(item)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func claimBadges(
        _ claim: EvidenceLinkedClaim
    ) -> some View {
        EvidenceBadge(
            title: label(claim.taxonomy.encodedValue),
            systemImage: "quote.bubble"
        )
        EvidenceBadge(
            title:
                "\(label(claim.supportStatus.encodedValue)) support",
            systemImage: "checkmark.shield"
        )
        EvidenceBadge(
            title:
                "\(confidenceLabel(claim.confidence)) confidence",
            systemImage:
                "gauge.with.dots.needle.50percent"
        )
    }

    @ViewBuilder
    private func exactEvidenceReferences(
        _ claim: EvidenceLinkedClaim
    ) -> some View {
        let references = Array(
            Set(claim.evidenceRevisions)
        ).sorted()
        if references.isEmpty {
            WorkflowStateView(
                title: "No exact evidence reference",
                detail:
                    "No EvidenceRef is implied for this claim.",
                systemImage: "link.badge.plus",
                tone: .failure
            )
        } else {
            DisclosureGroup(
                "Exact EvidenceRef revisions (\(references.count))"
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        "The Briefing review bundle retains exact references but does not include an application-owned EvidenceRef projection. No Briefing evidence inspector is shown."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ForEach(references, id: \.self) {
                        reference in
                        exactReference(
                            reference,
                            title: "EvidenceRef"
                        )
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private func exactSourceReferences(
        _ item: BriefingSectionItem
    ) -> some View {
        DisclosureGroup(
            "Exact source objects (\(item.sourceObjectRevisions.count))"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(
                    item.sourceObjectRevisions,
                    id: \.self
                ) { reference in
                    exactReference(
                        reference,
                        title: label(
                            reference.objectType
                                .encodedValue
                        )
                    )
                }
                Text(
                    "Commitment and Decision references are document evidence only; this canvas exposes no status mutation control."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }
    }

    private func exactReference(
        _ reference: SemanticRevisionReference,
        title: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            EvidenceBadge(
                title: title,
                systemImage: "link.circle"
            )
            Text(reference.logicalID.canonicalString)
                .font(.caption.monospaced())
            Text(
                "revision \(reference.revisionID.canonicalString)"
            )
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(title) exact semantic revision"
        )
        .accessibilityValue(
            "\(reference.logicalID.canonicalString), revision \(reference.revisionID.canonicalString)"
        )
    }

    private func sectionStatus(
        _ section: BriefingSectionV1
    ) -> String {
        [
            label(section.manualEditStatus.encodedValue),
            section.locked ? "Locked" : "Unlocked",
            section.userConfirmed
                ? "Human confirmed"
                : "Confirmation incomplete"
        ].joined(separator: " · ")
    }

    private func confidenceLabel(
        _ confidence: ConfidenceScore
    ) -> String {
        let percent =
            Double(confidence.millionths) / 10_000
        return percent.formatted(
            .number.precision(.fractionLength(1))
        ) + "%"
    }

    private func label(
        _ rawValue: String
    ) -> String {
        rawValue
            .replacingOccurrences(
                of: "_",
                with: " "
            )
            .capitalized
    }

    private func short(
        _ value: String
    ) -> String {
        value.count > 18
            ? String(value.prefix(18)) + "…"
            : value
    }
}

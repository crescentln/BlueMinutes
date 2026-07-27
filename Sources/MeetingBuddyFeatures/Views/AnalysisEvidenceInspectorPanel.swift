import MeetingBuddyDomain
import SwiftUI

struct AnalysisEvidenceInspectorPanel: View {
    let selection: AnalysisEvidenceSelection?
    let evidence: EvidenceRefV1?
    let ledgerIsHumanConfirmed: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Analysis Evidence Inspector")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                if let selection {
                    claimSection(selection)
                    evidenceSection(selection)
                } else {
                    WorkflowStateView(
                        title: "Select an Evidence Anchor",
                        detail:
                            "Open an evidence anchor from a claim or Position to inspect its exact application-owned EvidenceRef revision.",
                        systemImage: "link.circle",
                        tone: .neutral
                    )
                }
            }
            .padding(18)
            .textSelection(.enabled)
        }
        .accessibilityIdentifier(
            "BlueMinutes.Analysis.EvidenceInspector"
        )
        .accessibilityLabel(
            "Analysis evidence inspector"
        )
        .accessibilityValue(
            selection == nil
                ? "No evidence anchor selected"
                : evidence == nil
                    ? "Selected evidence revision is unresolved"
                    : "Selected evidence revision resolved exactly"
        )
    }

    private func claimSection(
        _ selection: AnalysisEvidenceSelection
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorialSectionHeader(
                selection.context,
                detail:
                    "Confidence, evidence support, model provenance, and whole-ledger human confirmation are separate review facts."
            )
            Text(selection.claim.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent(
                "Claim taxonomy",
                value: label(selection.claim.taxonomy.encodedValue)
            )
            LabeledContent(
                "Evidence support",
                value: label(
                    selection.claim.supportStatus.encodedValue
                )
            )
            LabeledContent(
                "Claim confidence",
                value: confidenceLabel(selection.claim.confidence)
            )
            LabeledContent(
                "Whole-ledger human confirmation",
                value: ledgerIsHumanConfirmed ? "Confirmed" : "Not confirmed"
            )
            Text(
                "This inspector does not grant per-claim confirmation authority."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func evidenceSection(
        _ selection: AnalysisEvidenceSelection
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorialSectionHeader(
                "Exact evidence revision",
                detail:
                    "Resolution uses the complete logical ID and revision ID. Missing or duplicate objects fail closed."
            )
            LabeledContent(
                "Referenced object",
                value: label(
                    selection.evidenceReference.objectType
                        .encodedValue
                )
            )
            LabeledContent(
                "Referenced logical ID",
                value:
                    selection.evidenceReference.logicalID
                    .canonicalString
            )
            LabeledContent(
                "Referenced revision",
                value:
                    selection.evidenceReference.revisionID
                    .canonicalString
            )
            if let evidence {
                EvidenceRefDetailsView(evidence: evidence)
            } else {
                WorkflowStateView(
                    title: "Evidence resolution failed closed",
                    detail:
                        "The exact referenced EvidenceRef revision is missing or ambiguous and is not represented as resolved evidence.",
                    systemImage: "exclamationmark.triangle",
                    tone: .failure
                )
            }
        }
    }

    private func confidenceLabel(
        _ confidence: ConfidenceScore
    ) -> String {
        let percent = Double(confidence.millionths) / 10_000
        return percent.formatted(
            .number.precision(.fractionLength(1))
        ) + "%"
    }

    private func label(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

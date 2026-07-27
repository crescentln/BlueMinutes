import MeetingBuddyDomain
import SwiftUI

struct EvidenceAnchor: View {
    let evidence: EvidenceRefV1
    let inspect: @MainActor () -> Void

    var body: some View {
        Button {
            inspect()
        } label: {
            Label(
                evidenceKindLabel,
                systemImage: "link.circle"
            )
        }
        .buttonStyle(.link)
        .accessibilityLabel(
            "\(evidenceKindLabel), evidence revision "
                + evidence.revision.revisionID.canonicalString
        )
        .accessibilityHint(
            "Open the inspector and select this exact EvidenceRef revision."
        )
    }

    private var evidenceKindLabel: String {
        evidence.evidenceKind.rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

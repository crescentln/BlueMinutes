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
        .accessibilityHint(
            "Open the inspector for exact EvidenceRef revision \(shortRevision)."
        )
    }

    private var evidenceKindLabel: String {
        evidence.evidenceKind.rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private var shortRevision: String {
        String(
            evidence.revision.revisionID.canonicalString.prefix(12)
        )
    }
}

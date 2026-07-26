import SwiftUI

struct EvidenceBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.secondary.opacity(0.12), in: Capsule())
            .accessibilityLabel(title)
    }
}

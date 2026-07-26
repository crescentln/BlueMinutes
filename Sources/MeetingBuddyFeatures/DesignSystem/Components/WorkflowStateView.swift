import SwiftUI

enum WorkflowStateTone: Sendable {
    case neutral
    case ready
    case warning
    case working
    case success
    case failure

    @MainActor
    var color: Color {
        switch self {
        case .neutral:
            .secondary
        case .ready:
            .blue
        case .warning:
            .orange
        case .working:
            .blue
        case .success:
            .green
        case .failure:
            BlueMinutesColors.error
        }
    }
}

struct WorkflowStateView: View {
    let title: String
    let detail: String
    let systemImage: String
    let tone: WorkflowStateTone

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tone.color)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(detail)
    }
}

import SwiftUI

enum WorkspaceSidebarRowAvailability: Equatable, Sendable {
    case enabled
    case prerequisiteUnavailable(reason: String)
    case temporarilyUnavailable(reason: String)

    static func resolve(
        prerequisiteReason: String?,
        temporaryReason: String?
    ) -> Self {
        if let prerequisiteReason {
            return .prerequisiteUnavailable(reason: prerequisiteReason)
        }
        if let temporaryReason {
            return .temporarilyUnavailable(reason: temporaryReason)
        }
        return .enabled
    }

    func resolvedHint(enabledHint: String) -> String {
        switch self {
        case .enabled:
            enabledHint
        case let .prerequisiteUnavailable(reason),
             let .temporarilyUnavailable(reason):
            reason
        }
    }
}

struct WorkspaceSidebarRow: View {
    let title: String
    let icon: BlueMinutesIconRole
    let enabledHint: String
    let availability: WorkspaceSidebarRowAvailability

    init(
        title: String,
        icon: BlueMinutesIconRole,
        enabledHint: String,
        availability: WorkspaceSidebarRowAvailability
    ) {
        self.title = title
        self.icon = icon
        self.enabledHint = enabledHint
        self.availability = availability
    }

    var body: some View {
        HStack(spacing: BlueMinutesLayout.sidebarRowSpacing) {
            Image(systemName: icon.resolvedSystemName())
                .foregroundStyle(.secondary)
                .frame(width: BlueMinutesLayout.sidebarIconWidth)
                .accessibilityHidden(true)
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 4)
            if isPrerequisiteUnavailable {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(availability.resolvedHint(enabledHint: enabledHint))
        .help(availability.resolvedHint(enabledHint: enabledHint))
    }

    private var isPrerequisiteUnavailable:
        Bool
    {
        if case .prerequisiteUnavailable =
            availability
        {
            return true
        }
        return false
    }
}

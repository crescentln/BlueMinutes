import SwiftUI

struct WorkspaceSidebarRow: View {
    @Environment(\.isEnabled) private var isEnabled

    let title: String
    let icon: BlueMinutesIconRole
    let enabledHint: String
    let disabledReason: String?

    init(
        title: String,
        icon: BlueMinutesIconRole,
        enabledHint: String,
        disabledReason: String? = nil
    ) {
        self.title = title
        self.icon = icon
        self.enabledHint = enabledHint
        self.disabledReason = disabledReason
    }

    var body: some View {
        HStack(spacing: BlueMinutesLayout.sidebarRowSpacing) {
            Image(systemName: icon.resolvedSystemName())
                .foregroundStyle(.secondary)
                .frame(width: BlueMinutesLayout.sidebarIconWidth)
                .accessibilityHidden(true)
            Text(title)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(resolvedHint)
        .help(resolvedHint)
    }

    private var resolvedHint: String {
        if isEnabled {
            return enabledHint
        }
        return disabledReason ?? "\(title) is unavailable."
    }
}

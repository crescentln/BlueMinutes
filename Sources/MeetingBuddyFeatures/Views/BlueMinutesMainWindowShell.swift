import SwiftUI

@MainActor
public struct BlueMinutesShellCommandActions {
    let canChooseWorkspace: Bool
    private let chooseWorkspaceAction: @MainActor () -> Void

    init(
        canChooseWorkspace: Bool,
        chooseWorkspace: @escaping @MainActor () -> Void
    ) {
        self.canChooseWorkspace = canChooseWorkspace
        chooseWorkspaceAction = chooseWorkspace
    }

    func chooseWorkspace() {
        chooseWorkspaceAction()
    }
}

private struct BlueMinutesShellCommandActionsKey: FocusedValueKey {
    typealias Value = BlueMinutesShellCommandActions
}

public extension FocusedValues {
    var blueMinutesShellCommandActions: BlueMinutesShellCommandActions? {
        get { self[BlueMinutesShellCommandActionsKey.self] }
        set { self[BlueMinutesShellCommandActionsKey.self] = newValue }
    }
}

@MainActor
public struct BlueMinutesShellCommands: Commands {
    @FocusedValue(\.blueMinutesShellCommandActions)
    private var actions

    public init() {}

    public var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Choose Workspace…") {
                actions?.chooseWorkspace()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(actions?.canChooseWorkspace != true)
        }
    }
}

struct BlueMinutesEditorialCanvas<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(
                minWidth: BlueMinutesLayout.editorialCanvasMinimumWidth,
                maxWidth: .infinity,
                maxHeight: .infinity
            )
            .background(BlueMinutesColors.canvas)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("BlueMinutes.EditorialCanvas")
    }
}

struct BlueMinutesEditorialToolbarContent: ToolbarContent {
    let workspaceTitle: String?
    let canChooseWorkspace: Bool
    let workspaceSwitchUnavailableReason: String?
    let isWorking: Bool
    let chooseWorkspace: @MainActor () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            BlueMinutesWorkspaceToolbarMenu(
                workspaceTitle: workspaceTitle,
                canChooseWorkspace: canChooseWorkspace,
                workspaceSwitchUnavailableReason:
                    workspaceSwitchUnavailableReason,
                chooseWorkspace: chooseWorkspace
            )
        }

        if isWorking {
            ToolbarItem(placement: .status) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Current operation in progress")
            }
        }
    }
}

private struct BlueMinutesWorkspaceToolbarMenu: View {
    let workspaceTitle: String?
    let canChooseWorkspace: Bool
    let workspaceSwitchUnavailableReason: String?
    let chooseWorkspace: @MainActor () -> Void

    var body: some View {
        Menu {
            Button("Choose Workspace…") {
                chooseWorkspace()
            }
            .disabled(!canChooseWorkspace)
            if let workspaceSwitchUnavailableReason {
                Divider()
                Text(workspaceSwitchUnavailableReason)
            }
        } label: {
            Label(
                workspaceTitle ?? "Choose Workspace",
                systemImage: icon.resolvedSystemName()
            )
            .lineLimit(1)
            .truncationMode(.middle)
        }
        .help(helpText)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(
            workspaceSwitchUnavailableReason
                ?? "Open the menu to choose a different local workspace."
        )
    }

    private var icon: BlueMinutesIconRole {
        workspaceTitle == nil ? .workspaceUnavailable : .workspace
    }

    private var helpText: String {
        if let workspaceTitle {
            "Current local workspace: \(workspaceTitle)"
        } else {
            "No local workspace is open."
        }
    }

    private var accessibilityLabel: String {
        if let workspaceTitle {
            "Current workspace: \(workspaceTitle)"
        } else {
            "No workspace open"
        }
    }
}

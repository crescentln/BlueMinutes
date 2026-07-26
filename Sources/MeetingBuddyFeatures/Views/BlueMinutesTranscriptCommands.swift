import SwiftUI

@MainActor
public struct BlueMinutesTranscriptCommandActions {
    let canSelectPrevious: Bool
    let canSelectNext: Bool
    let canSaveFocusedDraft: Bool
    private let selectPreviousAction: @MainActor () -> Void
    private let selectNextAction: @MainActor () -> Void
    private let saveFocusedDraftAction: @MainActor () -> Void
    private let toggleInspectorAction: @MainActor () -> Void

    init(
        canSelectPrevious: Bool,
        canSelectNext: Bool,
        canSaveFocusedDraft: Bool,
        selectPrevious: @escaping @MainActor () -> Void,
        selectNext: @escaping @MainActor () -> Void,
        saveFocusedDraft: @escaping @MainActor () -> Void,
        toggleInspector: @escaping @MainActor () -> Void
    ) {
        self.canSelectPrevious = canSelectPrevious
        self.canSelectNext = canSelectNext
        self.canSaveFocusedDraft = canSaveFocusedDraft
        selectPreviousAction = selectPrevious
        selectNextAction = selectNext
        saveFocusedDraftAction = saveFocusedDraft
        toggleInspectorAction = toggleInspector
    }

    func selectPrevious() {
        selectPreviousAction()
    }

    func selectNext() {
        selectNextAction()
    }

    func saveFocusedDraft() {
        saveFocusedDraftAction()
    }

    func toggleInspector() {
        toggleInspectorAction()
    }
}

private struct BlueMinutesTranscriptCommandActionsKey:
    FocusedValueKey
{
    typealias Value = BlueMinutesTranscriptCommandActions
}

public extension FocusedValues {
    var blueMinutesTranscriptCommandActions:
        BlueMinutesTranscriptCommandActions?
    {
        get { self[BlueMinutesTranscriptCommandActionsKey.self] }
        set { self[BlueMinutesTranscriptCommandActionsKey.self] = newValue }
    }
}

@MainActor
public struct BlueMinutesTranscriptCommands: Commands {
    @FocusedValue(\.blueMinutesTranscriptCommandActions)
    private var actions

    public init() {}

    public var body: some Commands {
        CommandMenu("Transcript") {
            Button("Previous Segment") {
                actions?.selectPrevious()
            }
            .keyboardShortcut(
                "[",
                modifiers: [.command, .option]
            )
            .disabled(actions?.canSelectPrevious != true)

            Button("Next Segment") {
                actions?.selectNext()
            }
            .keyboardShortcut(
                "]",
                modifiers: [.command, .option]
            )
            .disabled(actions?.canSelectNext != true)

            Divider()

            Button("Save Focused Transcript Draft") {
                actions?.saveFocusedDraft()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(actions?.canSaveFocusedDraft != true)

            Divider()

            Button("Toggle Evidence Inspector") {
                actions?.toggleInspector()
            }
            .keyboardShortcut(
                "i",
                modifiers: [.command, .option]
            )
            .disabled(actions == nil)
        }
    }
}

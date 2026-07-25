import AppKit

enum BlueMinutesIconRole: CaseIterable, Sendable {
    case workspace
    case workspaceUnavailable
    case chooseWorkspace
    case intake
    case recording
    case webMetadata
    case transcript
    case analysis
    case briefing
    case history
    case storage
    case success
    case failure
    case cancelled
    case paused
    case working

    var preferredSystemName: String {
        switch self {
        case .workspace:
            "folder"
        case .workspaceUnavailable:
            "folder.badge.questionmark"
        case .chooseWorkspace:
            "folder.badge.plus"
        case .intake:
            "waveform"
        case .recording:
            "record.circle"
        case .webMetadata:
            "link.badge.plus"
        case .transcript:
            "text.bubble"
        case .analysis:
            "checklist.checked"
        case .briefing:
            "doc.text.magnifyingglass"
        case .history:
            "clock.arrow.circlepath"
        case .storage:
            "externaldrive"
        case .success:
            "checkmark.circle.fill"
        case .failure:
            "exclamationmark.triangle.fill"
        case .cancelled:
            "xmark.circle"
        case .paused:
            "pause.circle"
        case .working:
            "gearshape.2"
        }
    }

    var fallbackSystemName: String {
        switch self {
        case .workspace, .workspaceUnavailable, .chooseWorkspace:
            "folder"
        case .intake:
            "doc"
        case .recording:
            "circle"
        case .webMetadata:
            "link"
        case .transcript:
            "text.alignleft"
        case .analysis, .success:
            "checkmark.circle"
        case .briefing:
            "doc.text"
        case .history:
            "clock"
        case .storage:
            "folder"
        case .failure:
            "exclamationmark.triangle"
        case .cancelled:
            "xmark"
        case .paused:
            "pause"
        case .working:
            "gearshape"
        }
    }

    @MainActor
    func resolvedSystemName(
        isAvailable: (String) -> Bool = { systemName in
            NSImage(
                systemSymbolName: systemName,
                accessibilityDescription: nil
            ) != nil
        }
    ) -> String {
        if isAvailable(preferredSystemName) {
            return preferredSystemName
        }
        if isAvailable(fallbackSystemName) {
            return fallbackSystemName
        }
        return "circle"
    }
}

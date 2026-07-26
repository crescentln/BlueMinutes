import MeetingBuddyApplication
import MeetingBuddyDomain
import Observation

@MainActor
@Observable
public final class LearnedPreferenceEditorState {
    public var kind: LearnedPreferenceKind = .briefingLength
    public var value = ""
    public var editingPreferenceID: LearnedPreferenceID?
    public var editingPreferenceVersion: UInt64?
    public var isResetConfirmationPresented = false

    public init() {}

    public func reset() {
        kind = .briefingLength
        value = ""
        editingPreferenceID = nil
        editingPreferenceVersion = nil
        isResetConfirmationPresented = false
    }
}

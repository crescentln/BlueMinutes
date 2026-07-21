import MeetingBuddyApplication
import MeetingBuddyDomain

public enum MediaReviewSection: Hashable, Sendable {
    case intake
    case recording
    case webMetadata
    case transcript
    case analysis
    case briefing
    case storage
}

public struct CaptureModeChoice: Identifiable, Hashable, Sendable {
    public let value: CaptureMode
    public let label: String
    public let detail: String
    public var id: String { value.rawValue }

    public init(value: CaptureMode, label: String, detail: String) {
        self.value = value
        self.label = label
        self.detail = detail
    }

    public static let all: [CaptureModeChoice] = [
        CaptureModeChoice(
            value: .microphoneOnly,
            label: "Microphone only",
            detail: "One explicitly selected microphone track"
        ),
        CaptureModeChoice(
            value: .applicationAudioOnly,
            label: "One application only",
            detail: "Audio from exactly one application selected in the system picker"
        ),
        CaptureModeChoice(
            value: .microphoneAndApplicationAudio,
            label: "Application and microphone",
            detail: "Two separate synchronized tracks; no authoritative mix"
        )
    ]
}

public struct ClassificationChoice: Identifiable, Hashable, Sendable {
    public let value: DataClassification
    public let label: String
    public var id: String { value.encodedValue }

    public init(value: DataClassification, label: String) {
        self.value = value
        self.label = label
    }

    public static let all: [ClassificationChoice] = [
        ClassificationChoice(value: .public, label: "Public"),
        ClassificationChoice(value: .internal, label: "Internal"),
        ClassificationChoice(value: .sensitive, label: "Sensitive"),
        ClassificationChoice(value: .restricted, label: "Restricted")
    ]
}

public struct SpeechKindChoice: Identifiable, Hashable, Sendable {
    public let value: SpeechSourceKind
    public let label: String
    public var id: String { value.encodedValue }

    public init(value: SpeechSourceKind, label: String) {
        self.value = value
        self.label = label
    }

    public static let all: [SpeechKindChoice] = [
        SpeechKindChoice(value: .originalSpeakerAudio, label: "Original speech"),
        SpeechKindChoice(value: .simultaneousInterpretation, label: "Simultaneous interpretation"),
        SpeechKindChoice(value: .translatedAudioTrack, label: "Translated audio"),
        SpeechKindChoice(value: .unknown, label: "Unknown")
    ]
}

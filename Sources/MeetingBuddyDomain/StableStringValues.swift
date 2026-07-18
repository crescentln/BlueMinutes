import Foundation

/// A string-backed value that preserves unknown future cases during decoding.
public protocol StableStringValue: Codable, Hashable, Sendable {
    init(encodedValue: String)
    var encodedValue: String { get }
    var isKnown: Bool { get }
}

public extension StableStringValue {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(encodedValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(encodedValue)
    }
}

public enum SemanticObjectType: StableStringValue {
    case sourceAsset
    case evidenceRef
    case meetingProfile
    case transcriptSegment
    case userConfirmedNote
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "source_asset": self = .sourceAsset
        case "evidence_ref": self = .evidenceRef
        case "meeting_profile": self = .meetingProfile
        case "transcript_segment": self = .transcriptSegment
        case "user_confirmed_note": self = .userConfirmedNote
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .sourceAsset: "source_asset"
        case .evidenceRef: "evidence_ref"
        case .meetingProfile: "meeting_profile"
        case .transcriptSegment: "transcript_segment"
        case .userConfirmedNote: "user_confirmed_note"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum LifecycleStatus: StableStringValue {
    case draft
    case published
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "draft": self = .draft
        case "published": self = .published
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .draft: "draft"
        case .published: "published"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum ValidationState: StableStringValue {
    case notValidated
    case valid
    case invalid
    case needsReview
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "not_validated": self = .notValidated
        case "valid": self = .valid
        case "invalid": self = .invalid
        case "needs_review": self = .needsReview
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .notValidated: "not_validated"
        case .valid: "valid"
        case .invalid: "invalid"
        case .needsReview: "needs_review"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum DataClassification: StableStringValue {
    case `public`
    case `internal`
    case sensitive
    case restricted
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "public": self = .public
        case "internal": self = .internal
        case "sensitive": self = .sensitive
        case "restricted": self = .restricted
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .public: "public"
        case .internal: "internal"
        case .sensitive: "sensitive"
        case .restricted: "restricted"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }

    /// Unknown classifications sort above known values so routing fails closed.
    public var restrictionRank: Int {
        switch self {
        case .public: 0
        case .internal: 1
        case .sensitive: 2
        case .restricted: 3
        case .unrecognized: 4
        }
    }

    public static func mostRestrictive(
        _ classifications: some Sequence<DataClassification>
    ) -> DataClassification? {
        classifications.max { lhs, rhs in
            if lhs.restrictionRank != rhs.restrictionRank {
                return lhs.restrictionRank < rhs.restrictionRank
            }
            return lhs.encodedValue < rhs.encodedValue
        }
    }
}

public enum SourceAssetType: StableStringValue {
    case audio
    case video
    case document
    case image
    case subtitle
    case other
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "audio": self = .audio
        case "video": self = .video
        case "document": self = .document
        case "image": self = .image
        case "subtitle": self = .subtitle
        case "other": self = .other
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .audio: "audio"
        case .video: "video"
        case .document: "document"
        case .image: "image"
        case .subtitle: "subtitle"
        case .other: "other"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum SourceOriginType: StableStringValue {
    case localImport
    case authorizedCapture
    case approvedWebSource
    case generated
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "local_import": self = .localImport
        case "authorized_capture": self = .authorizedCapture
        case "approved_web_source": self = .approvedWebSource
        case "generated": self = .generated
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .localImport: "local_import"
        case .authorizedCapture: "authorized_capture"
        case .approvedWebSource: "approved_web_source"
        case .generated: "generated"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum AcquisitionMethod: StableStringValue {
    case userSelectedFile
    case authorizedCapture
    case approvedHTTPSDownload
    case generated
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "user_selected_file": self = .userSelectedFile
        case "authorized_capture": self = .authorizedCapture
        case "approved_https_download": self = .approvedHTTPSDownload
        case "generated": self = .generated
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .userSelectedFile: "user_selected_file"
        case .authorizedCapture: "authorized_capture"
        case .approvedHTTPSDownload: "approved_https_download"
        case .generated: "generated"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum RetentionClass: StableStringValue {
    case permanent
    case workspaceManaged
    case temporary
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "permanent": self = .permanent
        case "workspace_managed": self = .workspaceManaged
        case "temporary": self = .temporary
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .permanent: "permanent"
        case .workspaceManaged: "workspace_managed"
        case .temporary: "temporary"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum SpeechSourceKind: StableStringValue {
    case originalSpeakerAudio
    case simultaneousInterpretation
    case translatedAudioTrack
    case unknown
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "original_speaker_audio": self = .originalSpeakerAudio
        case "simultaneous_interpretation": self = .simultaneousInterpretation
        case "translated_audio_track": self = .translatedAudioTrack
        case "unknown": self = .unknown
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .originalSpeakerAudio: "original_speaker_audio"
        case .simultaneousInterpretation: "simultaneous_interpretation"
        case .translatedAudioTrack: "translated_audio_track"
        case .unknown: "unknown"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum TranslationStatus: StableStringValue {
    case sourceOnly
    case machineTranslated
    case humanTranslated
    case simultaneousInterpretation
    case userEditedTranslation
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "source_only": self = .sourceOnly
        case "machine_translated": self = .machineTranslated
        case "human_translated": self = .humanTranslated
        case "simultaneous_interpretation": self = .simultaneousInterpretation
        case "user_edited_translation": self = .userEditedTranslation
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .sourceOnly: "source_only"
        case .machineTranslated: "machine_translated"
        case .humanTranslated: "human_translated"
        case .simultaneousInterpretation: "simultaneous_interpretation"
        case .userEditedTranslation: "user_edited_translation"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum HashAlgorithm: StableStringValue {
    case sha256
    case unrecognized(String)

    public init(encodedValue: String) {
        self = encodedValue == "sha256" ? .sha256 : .unrecognized(encodedValue)
    }

    public var encodedValue: String {
        switch self {
        case .sha256: "sha256"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum CreationActor: StableStringValue {
    case user
    case application
    case importProcess
    case provider
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "user": self = .user
        case "application": self = .application
        case "import_process": self = .importProcess
        case "provider": self = .provider
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .user: "user"
        case .application: "application"
        case .importProcess: "import_process"
        case .provider: "provider"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

/// The privacy-relevant processing route recorded for generated content.
public enum PrivacyRoute: StableStringValue {
    case localOnly
    case approvedCloud
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "local_only": self = .localOnly
        case "approved_cloud": self = .approvedCloud
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .localOnly: "local_only"
        case .approvedCloud: "approved_cloud"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

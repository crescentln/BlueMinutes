/// User-facing review state kept separate from schema validation state.
public enum ReviewStatus: StableStringValue {
    case unreviewed
    case needsReview
    case confirmed
    case rejected
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "unreviewed": self = .unreviewed
        case "needs_review": self = .needsReview
        case "confirmed": self = .confirmed
        case "rejected": self = .rejected
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .unreviewed: "unreviewed"
        case .needsReview: "needs_review"
        case .confirmed: "confirmed"
        case .rejected: "rejected"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

/// A meeting-level permission input; it never authorizes a provider by itself.
public enum MeetingCloudProcessingPolicy: StableStringValue {
    case localOnly
    case approvedCloudAllowed
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "local_only": self = .localOnly
        case "approved_cloud_allowed": self = .approvedCloudAllowed
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .localOnly: "local_only"
        case .approvedCloudAllowed: "approved_cloud_allowed"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum TranslationType: StableStringValue {
    case machineTranslation
    case humanTranslation
    case simultaneousInterpretationTranscript
    case userEditedTranslation
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "machine_translation": self = .machineTranslation
        case "human_translation": self = .humanTranslation
        case "simultaneous_interpretation_transcript": self = .simultaneousInterpretationTranscript
        case "user_edited_translation": self = .userEditedTranslation
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .machineTranslation: "machine_translation"
        case .humanTranslation: "human_translation"
        case .simultaneousInterpretationTranscript: "simultaneous_interpretation_transcript"
        case .userEditedTranslation: "user_edited_translation"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }

    public var evidenceTranslationStatus: TranslationStatus {
        switch self {
        case .machineTranslation: .machineTranslated
        case .humanTranslation: .humanTranslated
        case .simultaneousInterpretationTranscript: .simultaneousInterpretation
        case .userEditedTranslation: .userEditedTranslation
        case let .unrecognized(value): .unrecognized(value)
        }
    }
}

public enum AlignmentStatus: StableStringValue {
    case unreviewed
    case aligned
    case partiallyAligned
    case misaligned
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "unreviewed": self = .unreviewed
        case "aligned": self = .aligned
        case "partially_aligned": self = .partiallyAligned
        case "misaligned": self = .misaligned
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .unreviewed: "unreviewed"
        case .aligned: "aligned"
        case .partiallyAligned: "partially_aligned"
        case .misaligned: "misaligned"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum MeetingRole: StableStringValue {
    case delegate
    case chair
    case expert
    case observer
    case briefer
    case secretariatOfficial
    case groupRepresentative
    case unidentified
    case other
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "delegate": self = .delegate
        case "chair": self = .chair
        case "expert": self = .expert
        case "observer": self = .observer
        case "briefer": self = .briefer
        case "secretariat_official": self = .secretariatOfficial
        case "group_representative": self = .groupRepresentative
        case "unidentified": self = .unidentified
        case "other": self = .other
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .delegate: "delegate"
        case .chair: "chair"
        case .expert: "expert"
        case .observer: "observer"
        case .briefer: "briefer"
        case .secretariatOfficial: "secretariat_official"
        case .groupRepresentative: "group_representative"
        case .unidentified: "unidentified"
        case .other: "other"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum RepresentationKind: StableStringValue {
    case represents
    case speaksOnBehalfOf
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "represents": self = .represents
        case "speaks_on_behalf_of": self = .speaksOnBehalfOf
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .represents: "represents"
        case .speaksOnBehalfOf: "speaks_on_behalf_of"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum AssignmentCertainty: StableStringValue {
    case uncertain
    case probable
    case confirmed
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "uncertain": self = .uncertain
        case "probable": self = .probable
        case "confirmed": self = .confirmed
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .uncertain: "uncertain"
        case .probable: "probable"
        case .confirmed: "confirmed"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public enum SpeakerAssignmentSource: StableStringValue, Comparable {
    case officialSpeakerList
    case programme
    case chairIntroduction
    case transcriptContext
    case visibleNameplate
    case webChapterMetadata
    case knownSpeakingOrder
    case userCorrection
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "official_speaker_list": self = .officialSpeakerList
        case "programme": self = .programme
        case "chair_introduction": self = .chairIntroduction
        case "transcript_context": self = .transcriptContext
        case "visible_nameplate": self = .visibleNameplate
        case "web_chapter_metadata": self = .webChapterMetadata
        case "known_speaking_order": self = .knownSpeakingOrder
        case "user_correction": self = .userCorrection
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .officialSpeakerList: "official_speaker_list"
        case .programme: "programme"
        case .chairIntroduction: "chair_introduction"
        case .transcriptContext: "transcript_context"
        case .visibleNameplate: "visible_nameplate"
        case .webChapterMetadata: "web_chapter_metadata"
        case .knownSpeakingOrder: "known_speaking_order"
        case .userCorrection: "user_correction"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.encodedValue < rhs.encodedValue
    }
}

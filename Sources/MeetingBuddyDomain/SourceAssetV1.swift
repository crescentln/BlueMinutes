import Foundation

/// Optional media-only provenance attached to a SourceAsset.v1 contract.
public struct MediaProvenance: Codable, Hashable, Sendable, DomainValidatable {
    public let durationMilliseconds: UInt64
    public let containerFormat: String?
    public let codec: String?
    public let sampleRateHertz: UInt32?
    public let channelLayout: String?
    public let languageTrack: LanguageTag?
    public let speechSourceKind: SpeechSourceKind

    public init(
        durationMilliseconds: UInt64,
        containerFormat: String? = nil,
        codec: String? = nil,
        sampleRateHertz: UInt32? = nil,
        channelLayout: String? = nil,
        languageTrack: LanguageTag? = nil,
        speechSourceKind: SpeechSourceKind
    ) throws {
        self.durationMilliseconds = durationMilliseconds
        self.containerFormat = containerFormat
        self.codec = codec
        self.sampleRateHertz = sampleRateHertz
        self.channelLayout = channelLayout
        self.languageTrack = languageTrack
        self.speechSourceKind = speechSourceKind
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if durationMilliseconds == 0 {
            issues.append(
                ValidationIssue(
                    code: .invalidRange,
                    path: "media.duration_milliseconds",
                    message: "Media duration must be greater than zero."
                )
            )
        }
        if sampleRateHertz == 0 {
            issues.append(
                ValidationIssue(
                    code: .invalidRange,
                    path: "media.sample_rate_hertz",
                    message: "A present sample rate must be greater than zero."
                )
            )
        }
        for (value, path) in [
            (containerFormat, "media.container_format"),
            (codec, "media.codec"),
            (channelLayout, "media.channel_layout")
        ] {
            if let value,
               value != value.meetingBuddyTrimmed
                || value.isEmpty
                || value.utf8.count > 128
                || value.meetingBuddyContainsControlCharacter
            {
                issues.append(
                    ValidationIssue(
                        code: .invalidFormat,
                        path: path,
                        message: "Media descriptors must be non-empty, bounded text."
                    )
                )
            }
        }
        if let languageTrack {
            issues.append(contentsOf: languageTrack.validationIssues())
        }
        if !speechSourceKind.isKnown {
            issues.append(
                ValidationIssue(
                    code: .unsupportedValue,
                    path: "media.speech_source_kind",
                    message: "The speech source kind is not supported by SourceAsset.v1."
                )
            )
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        durationMilliseconds = try container.decode(UInt64.self, forKey: .durationMilliseconds)
        containerFormat = try container.decodeIfPresent(String.self, forKey: .containerFormat)
        codec = try container.decodeIfPresent(String.self, forKey: .codec)
        sampleRateHertz = try container.decodeIfPresent(UInt32.self, forKey: .sampleRateHertz)
        channelLayout = try container.decodeIfPresent(String.self, forKey: .channelLayout)
        languageTrack = try container.decodeIfPresent(LanguageTag.self, forKey: .languageTrack)
        speechSourceKind = try container.decode(SpeechSourceKind.self, forKey: .speechSourceKind)
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case durationMilliseconds = "duration_milliseconds"
        case containerFormat = "container_format"
        case codec
        case sampleRateHertz = "sample_rate_hertz"
        case channelLayout = "channel_layout"
        case languageTrack = "language_track"
        case speechSourceKind = "speech_source_kind"
    }
}

/// SourceAsset.v1 represents source material without exposing filesystem paths.
public struct SourceAssetV1: Codable, Hashable, Sendable, DomainValidatable {
    public let revision: RevisionEnvelope<SourceAssetIDTag>
    public let meetingID: MeetingID
    public let assetType: SourceAssetType
    public let originType: SourceOriginType
    public let sourceURL: HTTPSURL?
    public let managedStorageReference: ManagedAssetReference?
    public let sourceContentHash: ContentDigest
    public let mimeType: MIMEType
    public let byteSize: UInt64
    public let language: LanguageTag?
    public let acquisitionMethod: AcquisitionMethod
    public let acquiredAt: UTCInstant
    public let retentionClass: RetentionClass
    public let media: MediaProvenance?

    public init(
        revision: RevisionEnvelope<SourceAssetIDTag>,
        meetingID: MeetingID,
        assetType: SourceAssetType,
        originType: SourceOriginType,
        sourceURL: HTTPSURL? = nil,
        managedStorageReference: ManagedAssetReference? = nil,
        sourceContentHash: ContentDigest,
        mimeType: MIMEType,
        byteSize: UInt64,
        language: LanguageTag? = nil,
        acquisitionMethod: AcquisitionMethod,
        acquiredAt: UTCInstant,
        retentionClass: RetentionClass,
        media: MediaProvenance? = nil
    ) throws {
        self.revision = revision
        self.meetingID = meetingID
        self.assetType = assetType
        self.originType = originType
        self.sourceURL = sourceURL
        self.managedStorageReference = managedStorageReference
        self.sourceContentHash = sourceContentHash
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.language = language
        self.acquisitionMethod = acquisitionMethod
        self.acquiredAt = acquiredAt
        self.retentionClass = retentionClass
        self.media = media
        try validate()
    }

    public var assetID: SourceAssetID {
        revision.logicalID
    }

    /// SHA-256 of the documented semantic projection, excluding revision
    /// lifecycle/provenance and the relocatable managed-storage identifier.
    public func calculatedSemanticContentHash() throws -> ContentDigest {
        try SemanticHash.sha256(
            of: SemanticProjection(
                objectType: revision.objectType,
                schemaVersion: revision.schemaVersion,
                dataClassification: revision.dataClassification,
                inputRevisions: revision.inputRevisions,
                sourceAssetRevisions: revision.sourceAssetRevisions,
                evidenceRevisions: revision.evidenceRevisions,
                meetingID: meetingID,
                assetType: assetType,
                originType: originType,
                sourceURL: sourceURL,
                sourceContentHash: sourceContentHash,
                mimeType: mimeType,
                byteSize: byteSize,
                language: language,
                acquisitionMethod: acquisitionMethod,
                acquiredAt: acquiredAt,
                retentionClass: retentionClass,
                media: media
            )
        )
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = revision.validationIssues()
        if revision.objectType != .sourceAsset {
            issues.append(
                ValidationIssue(
                    code: .inconsistentValue,
                    path: "revision.object_type",
                    message: "SourceAsset.v1 requires the source_asset object type."
                )
            )
        }
        if revision.schemaVersion != .v1 {
            issues.append(
                ValidationIssue(
                    code: .unsupportedValue,
                    path: "revision.schema_version",
                    message: "SourceAsset.v1 supports schema version 1.0 only."
                )
            )
        }
        if !assetType.isKnown {
            issues.append(Self.unsupportedIssue(path: "asset_type", noun: "asset type"))
        }
        if !originType.isKnown {
            issues.append(Self.unsupportedIssue(path: "origin_type", noun: "origin type"))
        }
        if !acquisitionMethod.isKnown {
            issues.append(Self.unsupportedIssue(path: "acquisition_method", noun: "acquisition method"))
        }
        if !retentionClass.isKnown {
            issues.append(Self.unsupportedIssue(path: "retention_class", noun: "retention class"))
        }

        issues.append(contentsOf: sourceContentHash.validationIssues())
        issues.append(contentsOf: mimeType.validationIssues())
        if byteSize == 0 {
            issues.append(
                ValidationIssue(
                    code: .invalidRange,
                    path: "byte_size",
                    message: "A source asset must contain at least one byte."
                )
            )
        }
        if let language {
            issues.append(contentsOf: language.validationIssues())
        }
        issues.append(contentsOf: acquiredAt.validationIssues())
        if acquiredAt > revision.createdAt {
            issues.append(
                ValidationIssue(
                    code: .invalidRange,
                    path: "acquired_at",
                    message: "Source acquisition cannot occur after revision creation."
                )
            )
        }
        if let sourceURL {
            issues.append(contentsOf: sourceURL.validationIssues())
        }
        if let media {
            issues.append(contentsOf: media.validationIssues())
        }

        switch originType {
        case .localImport:
            issues.append(contentsOf: requireStorageAndMethod(.userSelectedFile))
        case .authorizedCapture:
            issues.append(contentsOf: requireStorageAndMethod(.authorizedCapture))
        case .approvedWebSource:
            issues.append(contentsOf: requireStorageAndMethod(.approvedHTTPSDownload))
            if sourceURL == nil {
                issues.append(
                    ValidationIssue(
                        code: .missingRequiredValue,
                        path: "source_url",
                        message: "An approved web source requires an HTTPS source URL."
                    )
                )
            }
        case .generated:
            issues.append(contentsOf: requireStorageAndMethod(.generated))
            if revision.generationMetadata == nil {
                issues.append(
                    ValidationIssue(
                        code: .missingRequiredValue,
                        path: "revision.generation_metadata",
                        message: "A generated source requires generation metadata."
                    )
                )
            }
        case .unrecognized:
            break
        }

        if let storedHash = revision.semanticContentHash {
            do {
                if storedHash != (try calculatedSemanticContentHash()) {
                    issues.append(
                        ValidationIssue(
                            code: .inconsistentValue,
                            path: "revision.semantic_content_hash",
                            message: "The stored semantic hash does not match SourceAsset.v1 content."
                        )
                    )
                }
            } catch {
                issues.append(
                    ValidationIssue(
                        code: .invalidFormat,
                        path: "revision.semantic_content_hash",
                        message: "SourceAsset.v1 semantic content could not be hashed canonically."
                    )
                )
            }
        }

        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(RevisionEnvelope<SourceAssetIDTag>.self, forKey: .revision)
        meetingID = try container.decode(MeetingID.self, forKey: .meetingID)
        assetType = try container.decode(SourceAssetType.self, forKey: .assetType)
        originType = try container.decode(SourceOriginType.self, forKey: .originType)
        sourceURL = try container.decodeIfPresent(HTTPSURL.self, forKey: .sourceURL)
        managedStorageReference = try container.decodeIfPresent(
            ManagedAssetReference.self,
            forKey: .managedStorageReference
        )
        sourceContentHash = try container.decode(ContentDigest.self, forKey: .sourceContentHash)
        mimeType = try container.decode(MIMEType.self, forKey: .mimeType)
        byteSize = try container.decode(UInt64.self, forKey: .byteSize)
        language = try container.decodeIfPresent(LanguageTag.self, forKey: .language)
        acquisitionMethod = try container.decode(AcquisitionMethod.self, forKey: .acquisitionMethod)
        acquiredAt = try container.decode(UTCInstant.self, forKey: .acquiredAt)
        retentionClass = try container.decode(RetentionClass.self, forKey: .retentionClass)
        media = try container.decodeIfPresent(MediaProvenance.self, forKey: .media)
        try validate()
    }

    private func requireStorageAndMethod(_ expectedMethod: AcquisitionMethod) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if managedStorageReference == nil {
            issues.append(
                ValidationIssue(
                    code: .missingRequiredValue,
                    path: "managed_storage_reference",
                    message: "This source origin requires an opaque managed-storage reference."
                )
            )
        }
        if acquisitionMethod != expectedMethod {
            issues.append(Self.methodMismatchIssue(expected: expectedMethod))
        }
        return issues
    }

    private static func methodMismatchIssue(expected: AcquisitionMethod) -> ValidationIssue {
        ValidationIssue(
            code: .inconsistentValue,
            path: "acquisition_method",
            message: "The acquisition method must be \(expected.encodedValue) for this source origin."
        )
    }

    private static func unsupportedIssue(path: String, noun: String) -> ValidationIssue {
        ValidationIssue(
            code: .unsupportedValue,
            path: path,
            message: "The \(noun) is not supported by SourceAsset.v1."
        )
    }

    private struct SemanticProjection: Encodable {
        let objectType: SemanticObjectType
        let schemaVersion: SchemaVersion
        let dataClassification: DataClassification
        let inputRevisions: [SemanticRevisionReference]
        let sourceAssetRevisions: [SemanticRevisionReference]
        let evidenceRevisions: [SemanticRevisionReference]
        let meetingID: MeetingID
        let assetType: SourceAssetType
        let originType: SourceOriginType
        let sourceURL: HTTPSURL?
        let sourceContentHash: ContentDigest
        let mimeType: MIMEType
        let byteSize: UInt64
        let language: LanguageTag?
        let acquisitionMethod: AcquisitionMethod
        let acquiredAt: UTCInstant
        let retentionClass: RetentionClass
        let media: MediaProvenance?

        private enum CodingKeys: String, CodingKey {
            case objectType = "object_type"
            case schemaVersion = "schema_version"
            case dataClassification = "data_classification"
            case inputRevisions = "input_revisions"
            case sourceAssetRevisions = "source_asset_revisions"
            case evidenceRevisions = "evidence_revisions"
            case meetingID = "meeting_id"
            case assetType = "asset_type"
            case originType = "origin_type"
            case sourceURL = "source_url"
            case sourceContentHash = "source_content_hash"
            case mimeType = "mime_type"
            case byteSize = "byte_size"
            case language
            case acquisitionMethod = "acquisition_method"
            case acquiredAt = "acquired_at"
            case retentionClass = "retention_class"
            case media
        }
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case meetingID = "meeting_id"
        case assetType = "asset_type"
        case originType = "origin_type"
        case sourceURL = "source_url"
        case managedStorageReference = "managed_storage_reference"
        case sourceContentHash = "source_content_hash"
        case mimeType = "mime_type"
        case byteSize = "byte_size"
        case language
        case acquisitionMethod = "acquisition_method"
        case acquiredAt = "acquired_at"
        case retentionClass = "retention_class"
        case media
    }
}

import Foundation

/// Provider-neutral generation provenance. It contains no credential or SDK type.
public struct ProviderMetadata: Codable, Hashable, Sendable, DomainValidatable {
    public let providerIdentifier: String
    public let modelIdentifier: String
    public let modelVersion: String?
    public let clientVersion: String?

    public init(
        providerIdentifier: String,
        modelIdentifier: String,
        modelVersion: String? = nil,
        clientVersion: String? = nil
    ) throws {
        self.providerIdentifier = providerIdentifier
        self.modelIdentifier = modelIdentifier
        self.modelVersion = modelVersion
        self.clientVersion = clientVersion
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        issues.append(contentsOf: Self.identifierIssues(providerIdentifier, path: "provider_metadata.provider_identifier"))
        issues.append(contentsOf: Self.identifierIssues(modelIdentifier, path: "provider_metadata.model_identifier"))
        if let modelVersion {
            issues.append(contentsOf: Self.optionalVersionIssues(modelVersion, path: "provider_metadata.model_version"))
        }
        if let clientVersion {
            issues.append(contentsOf: Self.optionalVersionIssues(clientVersion, path: "provider_metadata.client_version"))
        }
        return issues
    }

    private static func identifierIssues(_ value: String, path: String) -> [ValidationIssue] {
        let bytes = Array(value.utf8)
        let valid = !bytes.isEmpty
            && bytes.count <= 128
            && value == value.meetingBuddyTrimmed
            && !value.meetingBuddyContainsControlCharacter
            && !value.contains("/")
            && !value.contains("\\")
        guard !valid else { return [] }
        return [
            ValidationIssue(
                code: .invalidFormat,
                path: path,
                message: "Provider metadata identifiers must be bounded opaque names, not paths."
            )
        ]
    }

    private static func optionalVersionIssues(_ value: String, path: String) -> [ValidationIssue] {
        guard
            value == value.meetingBuddyTrimmed,
            !value.meetingBuddyTrimmed.isEmpty,
            value.utf8.count <= 128,
            !value.meetingBuddyContainsControlCharacter
        else {
            return [
                ValidationIssue(
                    code: .invalidFormat,
                    path: path,
                    message: "Version metadata must be non-empty, bounded text."
                )
            ]
        }
        return []
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerIdentifier = try container.decode(String.self, forKey: .providerIdentifier)
        modelIdentifier = try container.decode(String.self, forKey: .modelIdentifier)
        modelVersion = try container.decodeIfPresent(String.self, forKey: .modelVersion)
        clientVersion = try container.decodeIfPresent(String.self, forKey: .clientVersion)
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case providerIdentifier = "provider_identifier"
        case modelIdentifier = "model_identifier"
        case modelVersion = "model_version"
        case clientVersion = "client_version"
    }
}

/// A bounded opaque component name paired with its exact version.
public struct VersionedComponent: Codable, Hashable, Sendable, Comparable, DomainValidatable {
    public let identifier: String
    public let version: String

    public init(identifier: String, version: String) throws {
        self.identifier = identifier
        self.version = version
        try validate()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.identifier, lhs.version) < (rhs.identifier, rhs.version)
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if !Self.isBoundedOpaqueValue(identifier, allowSpaces: false) {
            issues.append(
                ValidationIssue(
                    code: .invalidFormat,
                    path: "versioned_component.identifier",
                    message: "A component identifier must be a bounded opaque name, not a path."
                )
            )
        }
        if !Self.isBoundedOpaqueValue(version, allowSpaces: true) {
            issues.append(
                ValidationIssue(
                    code: .invalidFormat,
                    path: "versioned_component.version",
                    message: "A component version must be non-empty, bounded text."
                )
            )
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decode(String.self, forKey: .identifier)
        version = try container.decode(String.self, forKey: .version)
        try validate()
    }

    private static func isBoundedOpaqueValue(_ value: String, allowSpaces: Bool) -> Bool {
        value == value.meetingBuddyTrimmed
            && !value.isEmpty
            && value.utf8.count <= 128
            && !value.meetingBuddyContainsControlCharacter
            && !value.contains("/")
            && !value.contains("\\")
            && (allowSpaces || !value.contains(" "))
    }

    private enum CodingKeys: String, CodingKey {
        case identifier
        case version
    }
}

/// Generation provenance for a semantic revision or generated source asset.
public struct GenerationMetadata: Codable, Hashable, Sendable, DomainValidatable {
    public let provider: ProviderMetadata
    public let promptModuleVersions: [VersionedComponent]
    public let outputSchemaVersion: SchemaVersion
    public let templateVersion: String
    public let generatedAt: UTCInstant
    public let privacyRoute: PrivacyRoute

    public init(
        provider: ProviderMetadata,
        promptModuleVersions: [VersionedComponent],
        outputSchemaVersion: SchemaVersion,
        templateVersion: String,
        generatedAt: UTCInstant,
        privacyRoute: PrivacyRoute
    ) throws {
        self.provider = provider
        self.promptModuleVersions = promptModuleVersions.sorted()
        self.outputSchemaVersion = outputSchemaVersion
        self.templateVersion = templateVersion
        self.generatedAt = generatedAt
        self.privacyRoute = privacyRoute
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = provider.validationIssues()
        if promptModuleVersions.isEmpty {
            issues.append(
                ValidationIssue(
                    code: .missingRequiredValue,
                    path: "generation_metadata.prompt_module_versions",
                    message: "Generated content must record at least one prompt or generator module version."
                )
            )
        }
        for component in promptModuleVersions {
            issues.append(contentsOf: component.validationIssues())
        }
        let identifiers = promptModuleVersions.map(\.identifier)
        if Set(identifiers).count != identifiers.count {
            issues.append(
                ValidationIssue(
                    code: .duplicateValue,
                    path: "generation_metadata.prompt_module_versions",
                    message: "A prompt or generator module may be recorded only once."
                )
            )
        }
        issues.append(contentsOf: outputSchemaVersion.validationIssues())
        if templateVersion != templateVersion.meetingBuddyTrimmed
            || templateVersion.isEmpty
            || templateVersion.utf8.count > 128
            || templateVersion.meetingBuddyContainsControlCharacter
        {
            issues.append(
                ValidationIssue(
                    code: .invalidFormat,
                    path: "generation_metadata.template_version",
                    message: "A template version must be non-empty, bounded text."
                )
            )
        }
        issues.append(contentsOf: generatedAt.validationIssues())
        if !privacyRoute.isKnown {
            issues.append(
                ValidationIssue(
                    code: .unsupportedValue,
                    path: "generation_metadata.privacy_route",
                    message: "The privacy route is not supported by this contract version."
                )
            )
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(ProviderMetadata.self, forKey: .provider)
        promptModuleVersions = try container.decode(
            [VersionedComponent].self,
            forKey: .promptModuleVersions
        ).sorted()
        outputSchemaVersion = try container.decode(
            SchemaVersion.self,
            forKey: .outputSchemaVersion
        )
        templateVersion = try container.decode(String.self, forKey: .templateVersion)
        generatedAt = try container.decode(UTCInstant.self, forKey: .generatedAt)
        privacyRoute = try container.decode(PrivacyRoute.self, forKey: .privacyRoute)
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case promptModuleVersions = "prompt_module_versions"
        case outputSchemaVersion = "output_schema_version"
        case templateVersion = "template_version"
        case generatedAt = "generated_at"
        case privacyRoute = "privacy_route"
    }
}

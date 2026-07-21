import Foundation
import MeetingBuddyDomain

/// A validated path relative to one MeetingBuddy workspace root.
///
/// Absolute paths and traversal components never cross this boundary. Concrete
/// storage adapters must still resolve symlinks and verify root confinement.
public struct WorkspaceRelativePath: Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let components = rawValue.split(separator: "/", omittingEmptySubsequences: false)
        guard !rawValue.isEmpty,
              rawValue.utf8.count <= 1_024,
              !rawValue.hasPrefix("/"),
              !rawValue.hasSuffix("/"),
              !rawValue.hasPrefix("~"),
              !rawValue.contains("\\"),
              !rawValue.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              components.allSatisfy({
                  !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255
              })
        else {
            throw WorkspaceContractError.invalidRelativePath(rawValue)
        }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum WorkspaceContractError: Error, Equatable, Sendable {
    case invalidRelativePath(String)
    case invalidWorkspaceRoot(String)
    case workspaceManifestMissing
    case workspaceManifestMismatch(String)
    case pathEscapesWorkspace(String)
    case symbolicLinkNotAllowed(String)
    case managedAssetMismatch(String)
    case invalidStorageTransition(String)
    case recoveryArtifactInvalid(String)
}

public struct WorkspaceManifest: Codable, Hashable, Sendable {
    public static let currentFormatVersion: UInt32 = 1

    public let workspaceID: WorkspaceID
    public let formatVersion: UInt32
    public let createdAt: UTCInstant
    public let databasePath: WorkspaceRelativePath

    public init(
        workspaceID: WorkspaceID,
        formatVersion: UInt32 = currentFormatVersion,
        createdAt: UTCInstant,
        databasePath: WorkspaceRelativePath
    ) throws {
        guard formatVersion == Self.currentFormatVersion else {
            throw WorkspaceContractError.workspaceManifestMismatch(
                "Unsupported workspace format version \(formatVersion)."
            )
        }
        self.workspaceID = workspaceID
        self.formatVersion = formatVersion
        self.createdAt = createdAt
        self.databasePath = databasePath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            workspaceID: container.decode(WorkspaceID.self, forKey: .workspaceID),
            formatVersion: container.decode(UInt32.self, forKey: .formatVersion),
            createdAt: container.decode(UTCInstant.self, forKey: .createdAt),
            databasePath: container.decode(WorkspaceRelativePath.self, forKey: .databasePath)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace_id"
        case formatVersion = "format_version"
        case createdAt = "created_at"
        case databasePath = "database_path"
    }
}

public protocol WorkspaceService: Sendable {
    associatedtype Descriptor: Sendable

    func createWorkspace(
        at root: URL,
        workspaceID: WorkspaceID,
        createdAt: UTCInstant
    ) throws -> Descriptor

    func openWorkspace(at root: URL) throws -> Descriptor
}

public enum ManagedAssetState: String, Codable, Hashable, Sendable {
    case active
    case trashed
}

public struct ManagedFileExtension: Codable, Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let lowered = rawValue.lowercased()
        guard !lowered.isEmpty,
              lowered.utf8.count <= 16,
              lowered.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains)
        else {
            throw WorkspaceContractError.invalidRelativePath(rawValue)
        }
        self.rawValue = lowered
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ManagedAssetRecord: Codable, Hashable, Sendable {
    public let storageObjectID: StorageObjectID
    public let meetingID: MeetingID
    public let relativePath: WorkspaceRelativePath
    public let originalRelativePath: WorkspaceRelativePath
    public let contentHash: ContentDigest
    public let byteSize: UInt64
    public let createdAt: UTCInstant
    public let dataClassification: DataClassification
    public let retentionClass: RetentionClass
    public let state: ManagedAssetState
    public let trashedAt: UTCInstant?

    public init(
        storageObjectID: StorageObjectID,
        meetingID: MeetingID,
        relativePath: WorkspaceRelativePath,
        originalRelativePath: WorkspaceRelativePath? = nil,
        contentHash: ContentDigest,
        byteSize: UInt64,
        createdAt: UTCInstant,
        dataClassification: DataClassification,
        retentionClass: RetentionClass,
        state: ManagedAssetState = .active,
        trashedAt: UTCInstant? = nil
    ) throws {
        guard byteSize > 0 else {
            throw WorkspaceContractError.managedAssetMismatch(
                "A managed asset must contain at least one byte."
            )
        }
        guard contentHash.algorithm == .sha256 else {
            throw WorkspaceContractError.managedAssetMismatch(
                "Managed assets require a SHA-256 content hash."
            )
        }
        guard dataClassification.isKnown, retentionClass.isKnown else {
            throw WorkspaceContractError.managedAssetMismatch(
                "Managed asset classification and retention must be recognized values."
            )
        }
        switch state {
        case .active where trashedAt != nil:
            throw WorkspaceContractError.invalidStorageTransition(
                "An active managed asset cannot have a Trash timestamp."
            )
        case .trashed where trashedAt == nil:
            throw WorkspaceContractError.invalidStorageTransition(
                "A trashed managed asset requires a Trash timestamp."
            )
        default:
            break
        }
        if let trashedAt, trashedAt < createdAt {
            throw WorkspaceContractError.invalidStorageTransition(
                "A managed asset cannot enter Trash before it was created."
            )
        }
        let original = originalRelativePath ?? relativePath
        let originalComponents = original.rawValue.split(separator: "/", omittingEmptySubsequences: false)
        let isCanonicalMeetingAsset = originalComponents.count == 4
            && originalComponents[0] == "Meetings"
            && originalComponents[1] == meetingID.canonicalString
            && originalComponents[2] == "assets"
        let isCanonicalTemporaryRecordingAsset = originalComponents.count == 6
            && originalComponents[0] == "Meetings"
            && originalComponents[1] == meetingID.canonicalString
            && originalComponents[2] == "recordings"
            && UUID(uuidString: String(originalComponents[3]))
                .map { $0.uuidString.lowercased() } == String(originalComponents[3])
            && originalComponents[4] == "segments"
            && retentionClass == .temporary
        guard isCanonicalMeetingAsset || isCanonicalTemporaryRecordingAsset else {
            throw WorkspaceContractError.invalidStorageTransition(
                "A managed asset original path must use its canonical meeting asset or temporary recording directory."
            )
        }
        let filename = String(originalComponents[isCanonicalMeetingAsset ? 3 : 5])
        let identifier = storageObjectID.canonicalString
        let filenameIsCanonical: Bool
        if filename == identifier {
            filenameIsCanonical = true
        } else if filename.hasPrefix(identifier + ".") {
            let suffix = String(filename.dropFirst(identifier.count + 1))
            filenameIsCanonical = (try? ManagedFileExtension(suffix))?.rawValue == suffix
        } else {
            filenameIsCanonical = false
        }
        guard filenameIsCanonical else {
            throw WorkspaceContractError.invalidStorageTransition(
                "A managed asset filename must derive only from its storage object ID."
            )
        }

        let expectedTrashPath = ".Trash/assets/\(identifier)/\(filename)"
        if state == .active, relativePath != original {
            throw WorkspaceContractError.invalidStorageTransition(
                "An active managed asset must remain at its original non-Trash path."
            )
        }
        if state == .trashed, relativePath.rawValue != expectedTrashPath {
            throw WorkspaceContractError.invalidStorageTransition(
                "A trashed managed asset must use its canonical opaque Trash path."
            )
        }
        self.storageObjectID = storageObjectID
        self.meetingID = meetingID
        self.relativePath = relativePath
        self.originalRelativePath = original
        self.contentHash = contentHash
        self.byteSize = byteSize
        self.createdAt = createdAt
        self.dataClassification = dataClassification
        self.retentionClass = retentionClass
        self.state = state
        self.trashedAt = trashedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            storageObjectID: container.decode(StorageObjectID.self, forKey: .storageObjectID),
            meetingID: container.decode(MeetingID.self, forKey: .meetingID),
            relativePath: container.decode(WorkspaceRelativePath.self, forKey: .relativePath),
            originalRelativePath: container.decode(WorkspaceRelativePath.self, forKey: .originalRelativePath),
            contentHash: container.decode(ContentDigest.self, forKey: .contentHash),
            byteSize: container.decode(UInt64.self, forKey: .byteSize),
            createdAt: container.decode(UTCInstant.self, forKey: .createdAt),
            dataClassification: container.decode(DataClassification.self, forKey: .dataClassification),
            retentionClass: container.decode(RetentionClass.self, forKey: .retentionClass),
            state: container.decode(ManagedAssetState.self, forKey: .state),
            trashedAt: container.decodeIfPresent(UTCInstant.self, forKey: .trashedAt)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case storageObjectID = "storage_object_id"
        case meetingID = "meeting_id"
        case relativePath = "relative_path"
        case originalRelativePath = "original_relative_path"
        case contentHash = "content_hash"
        case byteSize = "byte_size"
        case createdAt = "created_at"
        case dataClassification = "data_classification"
        case retentionClass = "retention_class"
        case state
        case trashedAt = "trashed_at"
    }
}

public enum ManagedAssetDeletionMethod: String, Codable, Hashable, Sendable {
    /// Removes the directory entry only. APFS, snapshots, backups, and SSD
    /// behavior mean this is not a forensic-erasure guarantee.
    case filesystemUnlinkNoErasureGuarantee = "filesystem_unlink_no_erasure_guarantee"
}

public struct ManagedAssetPurgeAuthorization: Codable, Hashable, Sendable {
    public static let defaultMinimumRetentionDays: UInt16 = 30

    public let purgeID: UUID
    public let storageObjectID: StorageObjectID
    public let confirmedAt: UTCInstant
    public let minimumRetentionDays: UInt16
    public let visibleUserConfirmation: Bool
    public let acknowledgedDeletionMethod: ManagedAssetDeletionMethod

    public init(
        purgeID: UUID,
        storageObjectID: StorageObjectID,
        confirmedAt: UTCInstant,
        minimumRetentionDays: UInt16 = Self.defaultMinimumRetentionDays,
        visibleUserConfirmation: Bool,
        acknowledgedDeletionMethod: ManagedAssetDeletionMethod
    ) throws {
        guard minimumRetentionDays > 0,
              minimumRetentionDays <= 3_650,
              visibleUserConfirmation,
              acknowledgedDeletionMethod == .filesystemUnlinkNoErasureGuarantee
        else {
            throw WorkspaceContractError.invalidStorageTransition(
                "Permanent deletion requires visible confirmation, bounded retention, and an unlink-semantics acknowledgment."
            )
        }
        self.purgeID = purgeID
        self.storageObjectID = storageObjectID
        self.confirmedAt = confirmedAt
        self.minimumRetentionDays = minimumRetentionDays
        self.visibleUserConfirmation = visibleUserConfirmation
        self.acknowledgedDeletionMethod = acknowledgedDeletionMethod
    }

    public func validate(for record: ManagedAssetRecord) throws {
        guard record.storageObjectID == storageObjectID,
              record.state == .trashed,
              let trashedAt = record.trashedAt,
              confirmedAt >= (try Self.purgeEligibleAt(
                  trashedAt: trashedAt,
                  minimumRetentionDays: minimumRetentionDays
              ))
        else {
            throw WorkspaceContractError.invalidStorageTransition(
                "Only the confirmed Trash item may be unlinked after its retention interval."
            )
        }
    }

    public static func purgeEligibleAt(
        trashedAt: UTCInstant,
        minimumRetentionDays: UInt16 = defaultMinimumRetentionDays
    ) throws -> UTCInstant {
        let (duration, durationOverflow) = Int64(minimumRetentionDays)
            .multipliedReportingOverflow(by: 86_400_000)
        let (milliseconds, additionOverflow) = trashedAt.millisecondsSinceUnixEpoch
            .addingReportingOverflow(duration)
        guard !durationOverflow, !additionOverflow else {
            throw WorkspaceContractError.invalidStorageTransition(
                "The Trash retention deadline exceeded the supported timestamp range."
            )
        }
        return try UTCInstant(millisecondsSinceUnixEpoch: milliseconds)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            purgeID: container.decode(UUID.self, forKey: .purgeID),
            storageObjectID: container.decode(StorageObjectID.self, forKey: .storageObjectID),
            confirmedAt: container.decode(UTCInstant.self, forKey: .confirmedAt),
            minimumRetentionDays: container.decode(UInt16.self, forKey: .minimumRetentionDays),
            visibleUserConfirmation: container.decode(Bool.self, forKey: .visibleUserConfirmation),
            acknowledgedDeletionMethod: container.decode(ManagedAssetDeletionMethod.self, forKey: .acknowledgedDeletionMethod)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case purgeID = "purge_id"
        case storageObjectID = "storage_object_id"
        case confirmedAt = "confirmed_at"
        case minimumRetentionDays = "minimum_retention_days"
        case visibleUserConfirmation = "visible_user_confirmation"
        case acknowledgedDeletionMethod = "acknowledged_deletion_method"
    }
}

public struct ManagedAssetPurgeReceipt: Codable, Hashable, Sendable {
    public let purgeID: UUID
    public let storageObjectID: StorageObjectID
    public let purgedAt: UTCInstant
    public let deletionMethod: ManagedAssetDeletionMethod
    public let priorContentHash: ContentDigest
    public let priorByteSize: UInt64
    public let dataClassification: DataClassification

    public init(
        purgeID: UUID,
        storageObjectID: StorageObjectID,
        purgedAt: UTCInstant,
        deletionMethod: ManagedAssetDeletionMethod,
        priorContentHash: ContentDigest,
        priorByteSize: UInt64,
        dataClassification: DataClassification
    ) throws {
        guard deletionMethod == .filesystemUnlinkNoErasureGuarantee,
              priorContentHash.algorithm == .sha256,
              priorByteSize > 0,
              dataClassification.isKnown
        else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "The permanent-deletion receipt is incomplete."
            )
        }
        self.purgeID = purgeID
        self.storageObjectID = storageObjectID
        self.purgedAt = purgedAt
        self.deletionMethod = deletionMethod
        self.priorContentHash = priorContentHash
        self.priorByteSize = priorByteSize
        self.dataClassification = dataClassification
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            purgeID: container.decode(UUID.self, forKey: .purgeID),
            storageObjectID: container.decode(StorageObjectID.self, forKey: .storageObjectID),
            purgedAt: container.decode(UTCInstant.self, forKey: .purgedAt),
            deletionMethod: container.decode(ManagedAssetDeletionMethod.self, forKey: .deletionMethod),
            priorContentHash: container.decode(ContentDigest.self, forKey: .priorContentHash),
            priorByteSize: container.decode(UInt64.self, forKey: .priorByteSize),
            dataClassification: container.decode(DataClassification.self, forKey: .dataClassification)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case purgeID = "purge_id"
        case storageObjectID = "storage_object_id"
        case purgedAt = "purged_at"
        case deletionMethod = "deletion_method"
        case priorContentHash = "prior_content_hash"
        case priorByteSize = "prior_byte_size"
        case dataClassification = "data_classification"
    }
}

/// ID-based managed-file use case for features and composition roots.
///
/// Concrete record-based filesystem/repository coordination remains hidden
/// behind the implementation of this port.
public protocol StorageService: Sendable {
    func importFile(
        from authorizedSource: URL,
        meetingID: MeetingID,
        storageObjectID: StorageObjectID,
        fileExtension: ManagedFileExtension?,
        createdAt: UTCInstant,
        dataClassification: DataClassification,
        retentionClass: RetentionClass
    ) throws -> ManagedAssetRecord

    func moveToTrash(
        storageObjectID: StorageObjectID,
        at trashedAt: UTCInstant
    ) throws -> ManagedAssetRecord

    func restoreFromTrash(
        storageObjectID: StorageObjectID,
        at restoredAt: UTCInstant
    ) throws -> ManagedAssetRecord

    func permanentlyDeleteFromTrash(
        storageObjectID: StorageObjectID,
        authorization: ManagedAssetPurgeAuthorization
    ) throws -> ManagedAssetPurgeReceipt
}

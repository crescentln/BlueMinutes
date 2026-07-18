import Foundation
import MeetingBuddyDomain

public struct RecoveryArtifactDescriptor: Codable, Hashable, Sendable {
    public let relativePath: WorkspaceRelativePath
    public let contentHash: ContentDigest
    public let byteSize: UInt64

    public init(
        relativePath: WorkspaceRelativePath,
        contentHash: ContentDigest,
        byteSize: UInt64
    ) throws {
        guard contentHash.algorithm == .sha256, byteSize > 0 else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "Recovery artifacts require a SHA-256 hash and nonzero byte size."
            )
        }
        self.relativePath = relativePath
        self.contentHash = contentHash
        self.byteSize = byteSize
    }

    private enum CodingKeys: String, CodingKey {
        case relativePath = "relative_path"
        case contentHash = "content_hash"
        case byteSize = "byte_size"
    }
}

public struct DatabaseBackupDescriptor: Codable, Hashable, Sendable {
    public let artifact: RecoveryArtifactDescriptor
    public let createdAt: UTCInstant
    public let sourceSchemaVersion: UInt32

    public init(
        artifact: RecoveryArtifactDescriptor,
        createdAt: UTCInstant,
        sourceSchemaVersion: UInt32
    ) {
        self.artifact = artifact
        self.createdAt = createdAt
        self.sourceSchemaVersion = sourceSchemaVersion
    }

    private enum CodingKeys: String, CodingKey {
        case artifact
        case createdAt = "created_at"
        case sourceSchemaVersion = "source_schema_version"
    }
}

public struct MigrationOutcome: Codable, Hashable, Sendable {
    public let schemaVersion: UInt32
    public let appliedMigrations: [String]
    public let rollbackAnchor: DatabaseBackupDescriptor?

    public init(
        schemaVersion: UInt32,
        appliedMigrations: [String],
        rollbackAnchor: DatabaseBackupDescriptor?
    ) {
        self.schemaVersion = schemaVersion
        self.appliedMigrations = appliedMigrations
        self.rollbackAnchor = rollbackAnchor
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case appliedMigrations = "applied_migrations"
        case rollbackAnchor = "rollback_anchor"
    }
}

public struct RecoverySnapshotManifest: Codable, Hashable, Sendable {
    public static let currentFormatVersion: UInt32 = 1

    public let formatVersion: UInt32
    public let snapshotID: UUID
    public let workspaceID: WorkspaceID
    public let createdAt: UTCInstant
    public let schemaVersion: UInt32
    public let workspaceManifest: RecoveryArtifactDescriptor
    public let databaseBackup: RecoveryArtifactDescriptor
    public let semanticSnapshot: RecoveryArtifactDescriptor
    public let assetHashes: RecoveryArtifactDescriptor
    public let migrationVersion: RecoveryArtifactDescriptor
    public let revisionCount: UInt64
    public let managedAssetCount: UInt64
    public let semanticSnapshotIsExportOnly: Bool

    public init(
        formatVersion: UInt32 = currentFormatVersion,
        snapshotID: UUID,
        workspaceID: WorkspaceID,
        createdAt: UTCInstant,
        schemaVersion: UInt32,
        workspaceManifest: RecoveryArtifactDescriptor,
        databaseBackup: RecoveryArtifactDescriptor,
        semanticSnapshot: RecoveryArtifactDescriptor,
        assetHashes: RecoveryArtifactDescriptor,
        migrationVersion: RecoveryArtifactDescriptor,
        revisionCount: UInt64,
        managedAssetCount: UInt64,
        semanticSnapshotIsExportOnly: Bool = true
    ) throws {
        guard formatVersion == Self.currentFormatVersion else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "Unsupported recovery format version \(formatVersion)."
            )
        }
        self.formatVersion = formatVersion
        self.snapshotID = snapshotID
        self.workspaceID = workspaceID
        self.createdAt = createdAt
        self.schemaVersion = schemaVersion
        self.workspaceManifest = workspaceManifest
        self.databaseBackup = databaseBackup
        self.semanticSnapshot = semanticSnapshot
        self.assetHashes = assetHashes
        self.migrationVersion = migrationVersion
        self.revisionCount = revisionCount
        self.managedAssetCount = managedAssetCount
        self.semanticSnapshotIsExportOnly = semanticSnapshotIsExportOnly
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            formatVersion: container.decode(UInt32.self, forKey: .formatVersion),
            snapshotID: container.decode(UUID.self, forKey: .snapshotID),
            workspaceID: container.decode(WorkspaceID.self, forKey: .workspaceID),
            createdAt: container.decode(UTCInstant.self, forKey: .createdAt),
            schemaVersion: container.decode(UInt32.self, forKey: .schemaVersion),
            workspaceManifest: container.decode(
                RecoveryArtifactDescriptor.self,
                forKey: .workspaceManifest
            ),
            databaseBackup: container.decode(RecoveryArtifactDescriptor.self, forKey: .databaseBackup),
            semanticSnapshot: container.decode(RecoveryArtifactDescriptor.self, forKey: .semanticSnapshot),
            assetHashes: container.decode(RecoveryArtifactDescriptor.self, forKey: .assetHashes),
            migrationVersion: container.decode(RecoveryArtifactDescriptor.self, forKey: .migrationVersion),
            revisionCount: container.decode(UInt64.self, forKey: .revisionCount),
            managedAssetCount: container.decode(UInt64.self, forKey: .managedAssetCount),
            semanticSnapshotIsExportOnly: container.decode(
                Bool.self,
                forKey: .semanticSnapshotIsExportOnly
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case snapshotID = "snapshot_id"
        case workspaceID = "workspace_id"
        case createdAt = "created_at"
        case schemaVersion = "schema_version"
        case workspaceManifest = "workspace_manifest"
        case databaseBackup = "database_backup"
        case semanticSnapshot = "semantic_snapshot"
        case assetHashes = "asset_hashes"
        case migrationVersion = "migration_version"
        case revisionCount = "revision_count"
        case managedAssetCount = "managed_asset_count"
        case semanticSnapshotIsExportOnly = "semantic_snapshot_is_export_only"
    }
}

public protocol RecoveryService: Sendable {
    func createRecoverySnapshot(
        createdAt: UTCInstant
    ) throws -> RecoverySnapshotManifest

    func verifyRecoverySnapshot(_ manifest: RecoverySnapshotManifest) throws
}

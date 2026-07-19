import Foundation
import GRDB
import MeetingBuddyApplication
import MeetingBuddyDomain
import Testing
@testable import MeetingBuddyPersistence

@Suite(.serialized)
struct RecoveryAndTrashTests {
    @Test
    func recoverySnapshotIsSelfVerifyingAndTamperEvident() throws {
        let workspace = try DisposableMeetingBuddyWorkspace()
        defer { workspace.cleanup() }
        let store = try workspace.makeStore()
        defer { try? store.close() }
        try workspace.writeSource()
        let coordinator = ManagedAssetCoordinator(storage: workspace.storage, metadata: store)
        let record = try coordinator.importFile(
            from: workspace.sourceFile,
            meetingID: PersistenceFixtures.meetingID,
            storageObjectID: PersistenceFixtures.storageObjectID,
            fileExtension: try ManagedFileExtension("bin"),
            createdAt: PersistenceFixtures.createdAt,
            dataClassification: .internal,
            retentionClass: .permanent
        )
        try store.insert(PersistenceFixtures.meetingProfile())
        try store.insert(PersistenceFixtures.sourceAsset(record: record))

        let recovery = SQLiteRecoveryService(store: store, storage: workspace.storage)
        let manifest: RecoverySnapshotManifest
        do {
            manifest = try recovery.createRecoverySnapshot(createdAt: PersistenceFixtures.publishedAt)
        } catch {
            Issue.record("Recovery snapshot creation failed: \(error)")
            throw error
        }
        #expect(manifest.schemaVersion == SQLiteSchema.currentVersion)
        #expect(manifest.revisionCount == 2)
        #expect(manifest.managedAssetCount == 1)
        #expect(manifest.semanticSnapshotIsExportOnly)
        let databaseBackupURL = workspace.root
            .appendingPathComponent(manifest.databaseBackup.relativePath.rawValue)
        for suffix in ["-wal", "-shm", "-journal"] {
            #expect(!FileManager.default.fileExists(atPath: databaseBackupURL.path + suffix))
        }
        let snapshotDirectory = workspace.root
            .appendingPathComponent(manifest.databaseBackup.relativePath.rawValue)
            .deletingLastPathComponent()
        #expect(try posixMode(at: snapshotDirectory.deletingLastPathComponent()) == 0o700)
        #expect(try posixMode(at: snapshotDirectory) == 0o700)
        for artifact in [
            manifest.workspaceManifest,
            manifest.databaseBackup,
            manifest.semanticSnapshot,
            manifest.assetHashes,
            manifest.migrationVersion
        ] {
            #expect(
                try posixMode(at: workspace.root.appendingPathComponent(artifact.relativePath.rawValue))
                    == 0o600
            )
        }
        do {
            try recovery.verifyRecoverySnapshot(manifest)
        } catch {
            Issue.record("Recovery snapshot verification failed: \(error)")
            throw error
        }

        let semanticURL = workspace.root.appendingPathComponent(manifest.semanticSnapshot.relativePath.rawValue)
        let handle = try FileHandle(forWritingTo: semanticURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("tamper".utf8))
        try handle.close()
        #expect(throws: WorkspaceContractError.self) {
            try recovery.verifyRecoverySnapshot(manifest)
        }
    }

    @Test
    func recoveryRejectsMixedSnapshotPathsAndPayloadIndexMismatch() throws {
        let workspace = try DisposableMeetingBuddyWorkspace()
        defer { workspace.cleanup() }
        let store = try workspace.makeStore()
        defer { try? store.close() }
        try store.insert(PersistenceFixtures.meetingProfile())
        let recovery = SQLiteRecoveryService(store: store, storage: workspace.storage)
        let first = try recovery.createRecoverySnapshot(createdAt: PersistenceFixtures.publishedAt)
        let second = try recovery.createRecoverySnapshot(
            createdAt: PersistenceFixtures.replacementPublishedAt
        )

        let mixed = try RecoverySnapshotManifest(
            snapshotID: first.snapshotID,
            workspaceID: first.workspaceID,
            createdAt: first.createdAt,
            schemaVersion: first.schemaVersion,
            workspaceManifest: first.workspaceManifest,
            databaseBackup: second.databaseBackup,
            semanticSnapshot: first.semanticSnapshot,
            assetHashes: first.assetHashes,
            migrationVersion: first.migrationVersion,
            revisionCount: first.revisionCount,
            managedAssetCount: first.managedAssetCount
        )
        #expect(throws: WorkspaceContractError.self) {
            try recovery.verifyRecoverySnapshot(mixed)
        }

        let semanticURL = workspace.root
            .appendingPathComponent(first.semanticSnapshot.relativePath.rawValue)
        let original = try String(contentsOf: semanticURL, encoding: .utf8)
        let replacementLogicalID = PersistenceFixtures.id(103, MeetingID.self).canonicalString
        let indexedID = #""logical_id":"\#(PersistenceFixtures.meetingID.canonicalString)""#
        let alteredID = #""logical_id":"\#(replacementLogicalID)""#
        let altered = original.replacingOccurrences(of: indexedID, with: alteredID)
        #expect(altered != original)
        try Data(altered.utf8).write(to: semanticURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: semanticURL.path)
        let alteredDescriptor = try SQLiteDatabaseBootstrap.recoveryArtifact(
            at: semanticURL,
            workspaceRoot: workspace.root
        )
        let indexMismatch = try RecoverySnapshotManifest(
            snapshotID: first.snapshotID,
            workspaceID: first.workspaceID,
            createdAt: first.createdAt,
            schemaVersion: first.schemaVersion,
            workspaceManifest: first.workspaceManifest,
            databaseBackup: first.databaseBackup,
            semanticSnapshot: alteredDescriptor,
            assetHashes: first.assetHashes,
            migrationVersion: first.migrationVersion,
            revisionCount: first.revisionCount,
            managedAssetCount: first.managedAssetCount
        )
        #expect(throws: WorkspaceContractError.self) {
            try recovery.verifyRecoverySnapshot(indexMismatch)
        }
    }

    @Test
    func failedRegistrationLeavesRecoverableTrashCopyAndNoMetadata() throws {
        let workspace = try DisposableMeetingBuddyWorkspace()
        defer { workspace.cleanup() }
        let store = try workspace.makeStore()
        defer { try? store.close() }
        try workspace.writeSource()
        try store.databasePool.write { db in
            try db.execute(sql: """
                CREATE TRIGGER test_reject_managed_asset_registration
                BEFORE INSERT ON managed_assets
                BEGIN
                    SELECT RAISE(ABORT, 'intentional registration failure');
                END
                """)
        }
        let coordinator = ManagedAssetCoordinator(storage: workspace.storage, metadata: store)
        var recoveryRecord: ManagedAssetRecord?
        do {
            _ = try coordinator.importFile(
                from: workspace.sourceFile,
                meetingID: PersistenceFixtures.meetingID,
                storageObjectID: PersistenceFixtures.storageObjectID,
                fileExtension: try ManagedFileExtension("bin"),
                createdAt: PersistenceFixtures.createdAt,
                dataClassification: .internal,
                retentionClass: .permanent
            )
            Issue.record("The injected metadata failure unexpectedly succeeded.")
        } catch let error as ManagedAssetCoordinationError {
            if case let .registrationFailed(record, _) = error {
                recoveryRecord = record
            } else {
                Issue.record("Unexpected compensation result: \(error)")
            }
        }
        let trashed = try #require(recoveryRecord)
        #expect(trashed.state == .trashed)
        try workspace.storage.verifyFile(for: trashed)
        #expect(try store.managedAsset(storageObjectID: trashed.storageObjectID) == nil)
        #expect(
            !FileManager.default.fileExists(
                atPath: workspace.root
                    .appendingPathComponent(trashed.originalRelativePath.rawValue).path
            )
        )
        #expect(try Data(contentsOf: workspace.sourceFile) == PersistenceFixtures.sourceBytes)
    }

    @Test
    func failedTrashMetadataTransitionsRestoreThePriorFilesystemState() throws {
        let workspace = try DisposableMeetingBuddyWorkspace()
        defer { workspace.cleanup() }
        let store = try workspace.makeStore()
        defer { try? store.close() }
        try workspace.writeSource()
        let coordinator = ManagedAssetCoordinator(storage: workspace.storage, metadata: store)
        let active = try coordinator.importFile(
            from: workspace.sourceFile,
            meetingID: PersistenceFixtures.meetingID,
            storageObjectID: PersistenceFixtures.storageObjectID,
            fileExtension: try ManagedFileExtension("bin"),
            createdAt: PersistenceFixtures.createdAt,
            dataClassification: .internal,
            retentionClass: .permanent
        )
        let activeURL = workspace.root.appendingPathComponent(active.relativePath.rawValue)

        try installManagedAssetUpdateFailure(in: store)
        #expect(throws: ManagedAssetCoordinationError.self) {
            _ = try coordinator.moveToTrash(
                storageObjectID: active.storageObjectID,
                at: PersistenceFixtures.publishedAt
            )
        }
        #expect(try store.managedAsset(storageObjectID: active.storageObjectID) == active)
        #expect(try Data(contentsOf: activeURL) == PersistenceFixtures.sourceBytes)

        try removeManagedAssetUpdateFailure(from: store)
        let trashed = try coordinator.moveToTrash(
            storageObjectID: active.storageObjectID,
            at: PersistenceFixtures.publishedAt
        )
        let trashURL = workspace.root.appendingPathComponent(trashed.relativePath.rawValue)
        #expect(try Data(contentsOf: trashURL) == PersistenceFixtures.sourceBytes)

        try installManagedAssetUpdateFailure(in: store)
        #expect(throws: ManagedAssetCoordinationError.self) {
            _ = try coordinator.restoreFromTrash(
                storageObjectID: active.storageObjectID,
                at: PersistenceFixtures.replacementPublishedAt
            )
        }
        #expect(try store.managedAsset(storageObjectID: active.storageObjectID) == trashed)
        #expect(!FileManager.default.fileExists(atPath: activeURL.path))
        #expect(try Data(contentsOf: trashURL) == PersistenceFixtures.sourceBytes)
        try workspace.storage.verifyFile(for: trashed)
    }

    @Test
    func rejectedIntakeLeavesNoManagedOrStagingCopy() throws {
        let workspace = try DisposableMeetingBuddyWorkspace()
        defer { workspace.cleanup() }
        try workspace.writeSource()
        #expect(throws: WorkspaceContractError.self) {
            _ = try workspace.storage.storeFile(
                from: workspace.sourceFile,
                meetingID: PersistenceFixtures.meetingID,
                storageObjectID: PersistenceFixtures.storageObjectID,
                fileExtension: try ManagedFileExtension("bin"),
                createdAt: PersistenceFixtures.createdAt,
                dataClassification: .unrecognized("future-classification"),
                retentionClass: .permanent
            )
        }
        #expect(
            try FileManager.default.contentsOfDirectory(
                at: workspace.descriptor.layout.meetings,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
        #expect(
            try FileManager.default.contentsOfDirectory(
                at: workspace.descriptor.layout.temporary,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
        #expect(try Data(contentsOf: workspace.sourceFile) == PersistenceFixtures.sourceBytes)
    }

    @Test
    func trashAndRestorePreserveBytesAndNeverOverwriteCollision() throws {
        let workspace = try DisposableMeetingBuddyWorkspace()
        defer { workspace.cleanup() }
        let store = try workspace.makeStore()
        defer { try? store.close() }
        try workspace.writeSource()
        let coordinator = ManagedAssetCoordinator(storage: workspace.storage, metadata: store)
        let active = try coordinator.importFile(
            from: workspace.sourceFile,
            meetingID: PersistenceFixtures.meetingID,
            storageObjectID: PersistenceFixtures.storageObjectID,
            fileExtension: try ManagedFileExtension("bin"),
            createdAt: PersistenceFixtures.createdAt,
            dataClassification: .sensitive,
            retentionClass: .permanent
        )
        let activeURL = workspace.root.appendingPathComponent(active.relativePath.rawValue)
        #expect(try posixMode(at: activeURL.deletingLastPathComponent()) == 0o700)
        #expect(try posixMode(at: activeURL) == 0o600)
        #expect(throws: WorkspaceContractError.self) {
            _ = try workspace.storage.moveToTrash(active, at: PersistenceFixtures.acquiredAt)
        }
        #expect(try Data(contentsOf: activeURL) == PersistenceFixtures.sourceBytes)
        let trashed = try coordinator.moveToTrash(
            storageObjectID: active.storageObjectID,
            at: PersistenceFixtures.publishedAt
        )
        #expect(trashed.state == .trashed)
        #expect(try store.managedAsset(storageObjectID: active.storageObjectID) == trashed)
        try workspace.storage.verifyFile(for: trashed)

        let originalURL = workspace.root.appendingPathComponent(active.originalRelativePath.rawValue)
        try FileManager.default.createDirectory(
            at: originalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let collision = Data("unrelated-collision".utf8)
        try collision.write(to: originalURL, options: [.withoutOverwriting])
        #expect(throws: WorkspaceContractError.self) {
            _ = try coordinator.restoreFromTrash(
                storageObjectID: active.storageObjectID,
                at: PersistenceFixtures.replacementPublishedAt
            )
        }
        #expect(try Data(contentsOf: originalURL) == collision)
        #expect(try store.managedAsset(storageObjectID: active.storageObjectID)?.state == .trashed)

        try FileManager.default.removeItem(at: originalURL)
        let restored = try coordinator.restoreFromTrash(
            storageObjectID: active.storageObjectID,
            at: PersistenceFixtures.replacementPublishedAt
        )
        #expect(restored == active)
        #expect(try Data(contentsOf: originalURL) == PersistenceFixtures.sourceBytes)
        #expect(try store.managedAsset(storageObjectID: active.storageObjectID) == active)
        try workspace.storage.verifyFile(for: restored)
        let auditEvents = try store.databasePool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT event_kind, occurred_at_ms
                FROM managed_asset_events
                WHERE storage_object_id = ?
                ORDER BY occurred_at_ms
                """,
                arguments: [active.storageObjectID.canonicalString]
            ).map { row in
                (row["event_kind"] as String, row["occurred_at_ms"] as Int64)
            }
        }
        #expect(auditEvents.map(\.0) == ["registered", "trashed", "restored"])
        #expect(
            auditEvents.map(\.1) == [
                PersistenceFixtures.createdAt.millisecondsSinceUnixEpoch,
                PersistenceFixtures.publishedAt.millisecondsSinceUnixEpoch,
                PersistenceFixtures.replacementPublishedAt.millisecondsSinceUnixEpoch
            ]
        )
    }

    @Test
    func storageReportEnforcesRetentionAndRecordsRealisticPermanentDeletion() throws {
        let workspace = try DisposableMeetingBuddyWorkspace(suffix: "storage-dashboard-purge")
        defer { workspace.cleanup() }
        let store = try workspace.makeStore()
        defer { try? store.close() }
        try workspace.writeSource()
        let coordinator = ManagedAssetCoordinator(storage: workspace.storage, metadata: store)
        let active = try coordinator.importFile(
            from: workspace.sourceFile,
            meetingID: PersistenceFixtures.meetingID,
            storageObjectID: PersistenceFixtures.storageObjectID,
            fileExtension: try ManagedFileExtension("bin"),
            createdAt: PersistenceFixtures.createdAt,
            dataClassification: .sensitive,
            retentionClass: .permanent
        )
        let trashed = try coordinator.moveToTrash(
            storageObjectID: active.storageObjectID,
            at: PersistenceFixtures.publishedAt
        )
        let reporter = LocalWorkspaceStorageReporter(
            workspace: workspace.descriptor,
            store: store
        )
        let before = try reporter.storageReport(
            calculatedAt: PersistenceFixtures.replacementPublishedAt,
            maximumEntries: 1_000
        )
        #expect(!before.scanTruncated)
        #expect(before.permissionIssueCount == 0)
        #expect(before.trashItems.map(\.storageObjectID) == [active.storageObjectID])
        #expect(before.totalByteCount >= active.byteSize)

        let tooEarly = try ManagedAssetPurgeAuthorization(
            purgeID: UUID(),
            storageObjectID: active.storageObjectID,
            confirmedAt: PersistenceFixtures.replacementPublishedAt,
            visibleUserConfirmation: true,
            acknowledgedDeletionMethod: .filesystemUnlinkNoErasureGuarantee
        )
        #expect(throws: WorkspaceContractError.self) {
            _ = try coordinator.permanentlyDeleteFromTrash(
                storageObjectID: active.storageObjectID,
                authorization: tooEarly
            )
        }
        try workspace.storage.verifyFile(for: trashed)

        let eligibleAt = try ManagedAssetPurgeAuthorization.purgeEligibleAt(
            trashedAt: PersistenceFixtures.publishedAt
        )
        let authorization = try ManagedAssetPurgeAuthorization(
            purgeID: UUID(),
            storageObjectID: active.storageObjectID,
            confirmedAt: eligibleAt,
            visibleUserConfirmation: true,
            acknowledgedDeletionMethod: .filesystemUnlinkNoErasureGuarantee
        )
        let receipt = try coordinator.permanentlyDeleteFromTrash(
            storageObjectID: active.storageObjectID,
            authorization: authorization
        )
        #expect(receipt.deletionMethod == .filesystemUnlinkNoErasureGuarantee)
        #expect(receipt.priorContentHash == active.contentHash)
        #expect(receipt.priorByteSize == active.byteSize)
        #expect(
            try store.managedAssetPurgeReceipt(
                storageObjectID: active.storageObjectID
            ) == receipt
        )
        let trashURL = workspace.root.appendingPathComponent(trashed.relativePath.rawValue)
        #expect(!FileManager.default.fileExists(atPath: trashURL.path))
        #expect(throws: WorkspaceContractError.self) {
            _ = try coordinator.restoreFromTrash(
                storageObjectID: active.storageObjectID,
                at: eligibleAt
            )
        }
        let after = try reporter.storageReport(
            calculatedAt: eligibleAt,
            maximumEntries: 1_000
        )
        #expect(after.trashItems.isEmpty)
        #expect(
            try store.databasePool.read { db in
                try String.fetchOne(db, sql: "PRAGMA quick_check") == "ok"
                    && Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty
            }
        )
    }

    @Test
    func storageGrowthScanIsBoundedVisibleAndDetectsBroadPermissions() throws {
        let workspace = try DisposableMeetingBuddyWorkspace(suffix: "storage-growth-bound")
        defer { workspace.cleanup() }
        let store = try workspace.makeStore()
        defer { try? store.close() }
        let cache = workspace.root.appendingPathComponent("Cache", isDirectory: true)
        try FileManager.default.createDirectory(
            at: cache,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        for index in 0..<96 {
            let file = cache.appendingPathComponent(String(format: "entry-%03d.bin", index))
            #expect(FileManager.default.createFile(
                atPath: file.path,
                contents: Data(repeating: UInt8(truncatingIfNeeded: index), count: 128),
                attributes: [.posixPermissions: 0o600]
            ))
        }
        let reporter = LocalWorkspaceStorageReporter(
            workspace: workspace.descriptor,
            store: store
        )
        let bounded = try reporter.storageReport(
            calculatedAt: PersistenceFixtures.publishedAt,
            maximumEntries: 32
        )
        #expect(bounded.scanTruncated)
        #expect(bounded.categories.reduce(0) { $0 + $1.fileCount } <= 32)
        #expect(bounded.totalByteCount <= 32 * 128 + 1_000_000)

        let exposed = cache.appendingPathComponent("entry-000.bin")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: exposed.path
        )
        let full = try reporter.storageReport(
            calculatedAt: PersistenceFixtures.replacementPublishedAt,
            maximumEntries: 1_000
        )
        #expect(!full.scanTruncated)
        #expect(full.permissionIssueCount == 1)
        #expect(full.categories.first { $0.category == .logsAndCache }?.fileCount == 96)
    }

    @Test
    func startupRecoveryFinalizesInterruptedPermanentDeletionWithoutDataResurrection() async throws {
        let workspace = try DisposableMeetingBuddyWorkspace(suffix: "interrupted-purge")
        defer { workspace.cleanup() }
        try workspace.writeSource()
        var store = try workspace.makeStore()
        let normal = ManagedAssetCoordinator(storage: workspace.storage, metadata: store)
        let active = try normal.importFile(
            from: workspace.sourceFile,
            meetingID: PersistenceFixtures.meetingID,
            storageObjectID: PersistenceFixtures.storageObjectID,
            fileExtension: try ManagedFileExtension("bin"),
            createdAt: PersistenceFixtures.createdAt,
            dataClassification: .restricted,
            retentionClass: .permanent
        )
        let trashed = try normal.moveToTrash(
            storageObjectID: active.storageObjectID,
            at: PersistenceFixtures.publishedAt
        )
        let eligibleAt = try ManagedAssetPurgeAuthorization.purgeEligibleAt(
            trashedAt: PersistenceFixtures.publishedAt
        )
        let authorization = try ManagedAssetPurgeAuthorization(
            purgeID: UUID(),
            storageObjectID: active.storageObjectID,
            confirmedAt: eligibleAt,
            visibleUserConfirmation: true,
            acknowledgedDeletionMethod: .filesystemUnlinkNoErasureGuarantee
        )
        let interrupted = ManagedAssetCoordinator(
            storage: workspace.storage,
            metadata: store,
            injectedFaultPoint: .afterFilesystemBeforeJournal
        )
        #expect(throws: SimulatedManagedAssetProcessInterruption.self) {
            _ = try interrupted.permanentlyDeleteFromTrash(
                storageObjectID: active.storageObjectID,
                authorization: authorization
            )
        }
        #expect(
            !FileManager.default.fileExists(
                atPath: workspace.root.appendingPathComponent(trashed.relativePath.rawValue).path
            )
        )
        #expect(
            try store.unfinishedManagedAssetPurges(maximumOperations: 8).entries.count == 1
        )
        #expect(
            try store.managedAssetPurgeReceipt(
                storageObjectID: active.storageObjectID
            ) == nil
        )
        try store.close()

        store = try workspace.makeStore()
        defer { try? store.close() }
        let recovery = ManagedAssetCoordinator(storage: workspace.storage, metadata: store)
        let report = try await recovery.reconcileInterruptedOperations(
            at: eligibleAt,
            maximumOperations: 8
        )
        #expect(report.reconciledOperationCount == 1)
        #expect(report.rolledBackOperationCount == 0)
        #expect(report.repairRequiredOperationCount == 0)
        #expect(!report.truncated)
        let receipt = try store.managedAssetPurgeReceipt(
            storageObjectID: active.storageObjectID
        )
        #expect(receipt?.purgeID == authorization.purgeID)
        #expect(try store.unfinishedManagedAssetPurges(maximumOperations: 8).entries.isEmpty)
    }

    @Test
    func startupReconciliationCompletesInterruptedImportAfterReopen() async throws {
        let workspace = try DisposableMeetingBuddyWorkspace(suffix: "interrupted-import")
        defer { workspace.cleanup() }
        try workspace.writeSource()
        let initial = try workspace.makeStore()
        let interrupted = ManagedAssetCoordinator(
            storage: workspace.storage,
            metadata: initial,
            injectedFaultPoint: .afterFilesystemBeforeJournal
        )

        #expect(throws: SimulatedManagedAssetProcessInterruption.self) {
            _ = try interrupted.importFile(
                from: workspace.sourceFile,
                meetingID: PersistenceFixtures.meetingID,
                storageObjectID: PersistenceFixtures.storageObjectID,
                fileExtension: try ManagedFileExtension("bin"),
                createdAt: PersistenceFixtures.createdAt,
                dataClassification: .sensitive,
                retentionClass: .permanent
            )
        }
        #expect(
            try initial.managedAsset(
                storageObjectID: PersistenceFixtures.storageObjectID
            ) == nil
        )
        let unfinishedBefore = try initial.unfinishedManagedAssetOperations(maximumOperations: 8)
        #expect(unfinishedBefore.entries.count == 1)
        #expect(unfinishedBefore.entries.first?.state == .intent)
        try initial.close()

        let reopened = try workspace.makeStore()
        defer { try? reopened.close() }
        let recovery = ManagedAssetCoordinator(storage: workspace.storage, metadata: reopened)
        let report = try await recovery.reconcileInterruptedOperations(
            at: PersistenceFixtures.publishedAt,
            maximumOperations: 8
        )
        #expect(report.reconciledOperationCount == 1)
        #expect(report.rolledBackOperationCount == 0)
        #expect(report.repairRequiredOperationCount == 0)
        #expect(!report.truncated)

        let recoveredRecord = try reopened.managedAsset(
            storageObjectID: PersistenceFixtures.storageObjectID
        )
        let recovered = try #require(recoveredRecord)
        #expect(recovered.state == .active)
        try workspace.storage.verifyFile(for: recovered)
        #expect(try Data(contentsOf: workspace.sourceFile) == PersistenceFixtures.sourceBytes)
        #expect(
            try reopened.unfinishedManagedAssetOperations(maximumOperations: 8).entries.isEmpty
        )
        let completedState = try await reopened.databasePool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT state FROM managed_asset_operations"
            )
        }
        #expect(completedState == "completed")
    }

    @Test
    func startupReconciliationCompletesInterruptedTrashAndRestore() async throws {
        let workspace = try DisposableMeetingBuddyWorkspace(suffix: "interrupted-trash-restore")
        defer { workspace.cleanup() }
        try workspace.writeSource()
        var store = try workspace.makeStore()
        let normal = ManagedAssetCoordinator(storage: workspace.storage, metadata: store)
        let active = try normal.importFile(
            from: workspace.sourceFile,
            meetingID: PersistenceFixtures.meetingID,
            storageObjectID: PersistenceFixtures.storageObjectID,
            fileExtension: try ManagedFileExtension("bin"),
            createdAt: PersistenceFixtures.createdAt,
            dataClassification: .internal,
            retentionClass: .permanent
        )
        let interruptedTrash = ManagedAssetCoordinator(
            storage: workspace.storage,
            metadata: store,
            injectedFaultPoint: .afterFilesystemBeforeJournal
        )
        #expect(throws: SimulatedManagedAssetProcessInterruption.self) {
            _ = try interruptedTrash.moveToTrash(
                storageObjectID: active.storageObjectID,
                at: PersistenceFixtures.publishedAt
            )
        }
        #expect(try store.managedAsset(storageObjectID: active.storageObjectID) == active)
        try store.close()

        store = try workspace.makeStore()
        let trashRecovery = ManagedAssetCoordinator(storage: workspace.storage, metadata: store)
        let trashReport = try await trashRecovery.reconcileInterruptedOperations(
            at: PersistenceFixtures.replacementPublishedAt,
            maximumOperations: 8
        )
        #expect(trashReport.reconciledOperationCount == 1)
        let trashedRecord = try store.managedAsset(storageObjectID: active.storageObjectID)
        let trashed = try #require(trashedRecord)
        #expect(trashed.state == .trashed)
        try workspace.storage.verifyFile(for: trashed)

        let interruptedRestore = ManagedAssetCoordinator(
            storage: workspace.storage,
            metadata: store,
            injectedFaultPoint: .afterFilesystemBeforeJournal
        )
        #expect(throws: SimulatedManagedAssetProcessInterruption.self) {
            _ = try interruptedRestore.restoreFromTrash(
                storageObjectID: trashed.storageObjectID,
                at: PersistenceFixtures.replacementPublishedAt
            )
        }
        #expect(try store.managedAsset(storageObjectID: active.storageObjectID) == trashed)
        try store.close()

        store = try workspace.makeStore()
        defer { try? store.close() }
        let restoreRecovery = ManagedAssetCoordinator(storage: workspace.storage, metadata: store)
        let restoreReport = try await restoreRecovery.reconcileInterruptedOperations(
            at: try UTCInstant(
                millisecondsSinceUnixEpoch:
                    PersistenceFixtures.replacementPublishedAt.millisecondsSinceUnixEpoch + 1
            ),
            maximumOperations: 8
        )
        #expect(restoreReport.reconciledOperationCount == 1)
        #expect(restoreReport.repairRequiredOperationCount == 0)
        let restoredRecord = try store.managedAsset(storageObjectID: active.storageObjectID)
        let restored = try #require(restoredRecord)
        #expect(restored == active)
        try workspace.storage.verifyFile(for: restored)
        #expect(try store.unfinishedManagedAssetOperations(maximumOperations: 8).entries.isEmpty)
        let states = try await store.databasePool.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT state FROM managed_asset_operations ORDER BY created_at_ms, operation_id"
            )
        }
        #expect(states == ["completed", "completed", "completed"])
    }

    @Test
    func startupReconciliationRollsBackIntentAndRemovesOnlyOwnedStagingFile() async throws {
        let workspace = try DisposableMeetingBuddyWorkspace(suffix: "interrupted-intent")
        defer { workspace.cleanup() }
        try workspace.writeSource()
        let store = try workspace.makeStore()
        defer { try? store.close() }
        let interrupted = ManagedAssetCoordinator(
            storage: workspace.storage,
            metadata: store,
            injectedFaultPoint: .afterIntent
        )
        #expect(throws: SimulatedManagedAssetProcessInterruption.self) {
            _ = try interrupted.importFile(
                from: workspace.sourceFile,
                meetingID: PersistenceFixtures.meetingID,
                storageObjectID: PersistenceFixtures.storageObjectID,
                fileExtension: try ManagedFileExtension("bin"),
                createdAt: PersistenceFixtures.createdAt,
                dataClassification: .internal,
                retentionClass: .permanent
            )
        }
        let entry = try #require(
            store.unfinishedManagedAssetOperations(maximumOperations: 8).entries.first
        )
        let staging = workspace.descriptor.layout.temporary.appendingPathComponent(
            "managed-asset-\(entry.intent.operationID.uuidString.lowercased()).partial"
        )
        try Data("partial".utf8).write(to: staging, options: [.withoutOverwriting])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
        let unrelated = workspace.descriptor.layout.temporary.appendingPathComponent("unrelated.keep")
        try Data("keep".utf8).write(to: unrelated, options: [.withoutOverwriting])

        let recovery = ManagedAssetCoordinator(storage: workspace.storage, metadata: store)
        let report = try await recovery.reconcileInterruptedOperations(
            at: PersistenceFixtures.publishedAt,
            maximumOperations: 8
        )
        #expect(report.rolledBackOperationCount == 1)
        #expect(report.reconciledOperationCount == 0)
        #expect(!FileManager.default.fileExists(atPath: staging.path))
        #expect(try Data(contentsOf: unrelated) == Data("keep".utf8))
        #expect(try store.unfinishedManagedAssetOperations(maximumOperations: 8).entries.isEmpty)
    }

    private func installManagedAssetUpdateFailure(
        in store: SQLitePersistenceStore
    ) throws {
        try store.databasePool.write { db in
            try db.execute(sql: """
                CREATE TRIGGER test_reject_managed_asset_update
                BEFORE UPDATE ON managed_assets
                BEGIN
                    SELECT RAISE(ABORT, 'intentional managed asset update failure');
                END
                """)
        }
    }

    private func removeManagedAssetUpdateFailure(
        from store: SQLitePersistenceStore
    ) throws {
        try store.databasePool.write { db in
            try db.execute(sql: "DROP TRIGGER test_reject_managed_asset_update")
        }
    }
}

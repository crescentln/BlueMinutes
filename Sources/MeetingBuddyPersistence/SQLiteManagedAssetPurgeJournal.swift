import Foundation
import GRDB
import MeetingBuddyApplication
import MeetingBuddyDomain

enum ManagedAssetPurgeOperationState: String, Sendable {
    case intent
    case completed
    case rolledBack = "rolled_back"
    case repairRequired = "repair_required"
}

struct ManagedAssetPurgeIntent: Codable, Equatable, Sendable {
    let authorization: ManagedAssetPurgeAuthorization
    let record: ManagedAssetRecord

    init(
        authorization: ManagedAssetPurgeAuthorization,
        record: ManagedAssetRecord
    ) throws {
        try authorization.validate(for: record)
        self.authorization = authorization
        self.record = record
    }
}

struct ManagedAssetPurgeOperationEntry: Sendable {
    let intent: ManagedAssetPurgeIntent
    let state: ManagedAssetPurgeOperationState
    let receipt: ManagedAssetPurgeReceipt?
}

struct ManagedAssetPurgeOperationScan: Sendable {
    let entries: [ManagedAssetPurgeOperationEntry]
    let truncated: Bool
}

extension SQLitePersistenceStore {
    func beginManagedAssetPurge(_ intent: ManagedAssetPurgeIntent) throws {
        let payload = try SQLitePayloadCodec.canonicalData(intent)
        guard payload.count <= 1_048_576 else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "The permanent-deletion intent exceeds its bounded journal size."
            )
        }
        try databasePool.write { db in
            if let existing = try purgeOperation(
                purgeID: intent.authorization.purgeID,
                in: db
            ) {
                guard existing.intent == intent else {
                    throw PersistenceContractError.managedAssetConflict(
                        intent.record.storageObjectID
                    )
                }
                return
            }
            guard try purgeReceipt(
                storageObjectID: intent.record.storageObjectID,
                in: db
            ) == nil else {
                throw WorkspaceContractError.invalidStorageTransition(
                    "The managed asset already has a permanent-deletion receipt."
                )
            }
            try db.execute(
                sql: """
                INSERT INTO managed_asset_purge_operations(
                    operation_id, storage_object_id, state, requested_at_ms,
                    finished_at_ms, failure_code, intent_payload, intent_sha256,
                    intent_byte_size, receipt_payload, receipt_sha256,
                    receipt_byte_size
                ) VALUES (?, ?, 'intent', ?, NULL, NULL, ?, ?, ?, NULL, NULL, NULL)
                """,
                arguments: [
                    intent.authorization.purgeID.uuidString.lowercased(),
                    intent.record.storageObjectID.canonicalString,
                    intent.authorization.confirmedAt.millisecondsSinceUnixEpoch,
                    payload,
                    SQLitePayloadCodec.sha256(payload),
                    payload.count
                ]
            )
        }
    }

    func completeManagedAssetPurge(
        purgeID: UUID,
        receipt: ManagedAssetPurgeReceipt
    ) throws {
        let payload = try SQLitePayloadCodec.canonicalData(receipt)
        guard payload.count <= 1_048_576 else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "The permanent-deletion receipt exceeds its bounded journal size."
            )
        }
        try databasePool.write { db in
            guard let current = try purgeOperation(purgeID: purgeID, in: db),
                  current.intent.authorization.purgeID == purgeID,
                  current.intent.record.storageObjectID == receipt.storageObjectID,
                  receipt.purgeID == purgeID
            else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "The permanent-deletion journal entry is missing or inconsistent."
                )
            }
            if current.state == .completed {
                guard current.receipt == receipt else {
                    throw PersistenceContractError.managedAssetConflict(
                        receipt.storageObjectID
                    )
                }
                return
            }
            guard current.state == .intent || current.state == .repairRequired else {
                throw WorkspaceContractError.invalidStorageTransition(
                    "A rolled-back permanent deletion cannot be completed."
                )
            }
            if let existing = try purgeReceipt(
                storageObjectID: receipt.storageObjectID,
                in: db
            ) {
                guard existing == receipt else {
                    throw PersistenceContractError.managedAssetConflict(
                        receipt.storageObjectID
                    )
                }
            } else {
                try insertPurgeReceipt(receipt, payload: payload, in: db)
            }
            try db.execute(
                sql: """
                UPDATE managed_asset_purge_operations
                SET state = 'completed', finished_at_ms = ?, failure_code = NULL,
                    receipt_payload = ?, receipt_sha256 = ?, receipt_byte_size = ?
                WHERE operation_id = ?
                """,
                arguments: [
                    receipt.purgedAt.millisecondsSinceUnixEpoch,
                    payload,
                    SQLitePayloadCodec.sha256(payload),
                    payload.count,
                    purgeID.uuidString.lowercased()
                ]
            )
        }
    }

    func rollBackManagedAssetPurge(purgeID: UUID, at timestamp: UTCInstant) throws {
        try transitionManagedAssetPurge(
            purgeID: purgeID,
            state: .rolledBack,
            failureCode: nil,
            at: timestamp
        )
    }

    func markManagedAssetPurgeRepairRequired(
        purgeID: UUID,
        failureCode: String,
        at timestamp: UTCInstant
    ) throws {
        try transitionManagedAssetPurge(
            purgeID: purgeID,
            state: .repairRequired,
            failureCode: failureCode,
            at: timestamp
        )
    }

    func unfinishedManagedAssetPurges(
        maximumOperations: UInt32
    ) throws -> ManagedAssetPurgeOperationScan {
        guard maximumOperations > 0, maximumOperations <= 4_096 else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "Permanent-deletion reconciliation requires a bounded operation count."
            )
        }
        return try databasePool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM managed_asset_purge_operations
                WHERE state IN ('intent', 'repair_required')
                ORDER BY requested_at_ms, operation_id
                LIMIT ?
                """,
                arguments: [Int64(maximumOperations) + 1]
            )
            return try ManagedAssetPurgeOperationScan(
                entries: rows.prefix(Int(maximumOperations)).map {
                    try decodePurgeOperation(row: $0)
                },
                truncated: rows.count > Int(maximumOperations)
            )
        }
    }

    public func managedAssetPurgeReceipt(
        storageObjectID: StorageObjectID
    ) throws -> ManagedAssetPurgeReceipt? {
        try databasePool.read { db in
            try purgeReceipt(storageObjectID: storageObjectID, in: db)
        }
    }

    public func managedAssetPurgeReceipts() throws -> [ManagedAssetPurgeReceipt] {
        try databasePool.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM managed_asset_purge_receipts ORDER BY purged_at_ms, purge_id"
            ).map { try decodePurgeReceipt(row: $0) }
        }
    }

    private func transitionManagedAssetPurge(
        purgeID: UUID,
        state: ManagedAssetPurgeOperationState,
        failureCode: String?,
        at timestamp: UTCInstant
    ) throws {
        if let failureCode {
            guard !failureCode.isEmpty,
                  failureCode.utf8.count <= 96,
                  failureCode.utf8.allSatisfy({ byte in
                      (byte >= 97 && byte <= 122)
                          || (byte >= 48 && byte <= 57)
                          || byte == 95
                  })
            else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "A purge recovery failure code must be a bounded lowercase identifier."
                )
            }
        }
        try databasePool.write { db in
            guard let current = try purgeOperation(purgeID: purgeID, in: db) else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "The permanent-deletion journal entry is missing."
                )
            }
            if current.state == state { return }
            guard current.state == .intent || current.state == .repairRequired else {
                throw WorkspaceContractError.invalidStorageTransition(
                    "The permanent-deletion journal transition is not allowed."
                )
            }
            try db.execute(
                sql: """
                UPDATE managed_asset_purge_operations
                SET state = ?, finished_at_ms = ?, failure_code = ?
                WHERE operation_id = ?
                """,
                arguments: [
                    state.rawValue,
                    timestamp.millisecondsSinceUnixEpoch,
                    failureCode,
                    purgeID.uuidString.lowercased()
                ]
            )
        }
    }

    private func purgeOperation(
        purgeID: UUID,
        in db: Database
    ) throws -> ManagedAssetPurgeOperationEntry? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM managed_asset_purge_operations WHERE operation_id = ?",
            arguments: [purgeID.uuidString.lowercased()]
        ) else { return nil }
        return try decodePurgeOperation(row: row)
    }

    private func decodePurgeOperation(
        row: Row
    ) throws -> ManagedAssetPurgeOperationEntry {
        let payload: Data = row["intent_payload"]
        let digest: String = row["intent_sha256"]
        guard SQLitePayloadCodec.sha256(payload) == digest,
              (row["intent_byte_size"] as Int64) == Int64(payload.count),
              let state = ManagedAssetPurgeOperationState(
                  rawValue: row["state"] as String
              )
        else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "A permanent-deletion journal payload failed integrity validation."
            )
        }
        let intent = try JSONDecoder().decode(ManagedAssetPurgeIntent.self, from: payload)
        guard try SQLitePayloadCodec.canonicalData(intent) == payload,
              row["operation_id"] == intent.authorization.purgeID.uuidString.lowercased(),
              row["storage_object_id"] == intent.record.storageObjectID.canonicalString,
              (row["requested_at_ms"] as Int64)
                  == intent.authorization.confirmedAt.millisecondsSinceUnixEpoch
        else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "A permanent-deletion journal index does not match its payload."
            )
        }
        let receiptPayload: Data? = row["receipt_payload"]
        let receipt: ManagedAssetPurgeReceipt?
        if let receiptPayload {
            let receiptDigest: String? = row["receipt_sha256"]
            guard receiptDigest == SQLitePayloadCodec.sha256(receiptPayload),
                  (row["receipt_byte_size"] as Int64?) == Int64(receiptPayload.count)
            else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "A permanent-deletion receipt payload failed integrity validation."
                )
            }
            receipt = try JSONDecoder().decode(
                ManagedAssetPurgeReceipt.self,
                from: receiptPayload
            )
            guard try SQLitePayloadCodec.canonicalData(receipt) == receiptPayload else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "A permanent-deletion receipt is not canonical."
                )
            }
        } else {
            receipt = nil
        }
        return ManagedAssetPurgeOperationEntry(
            intent: intent,
            state: state,
            receipt: receipt
        )
    }

    private func insertPurgeReceipt(
        _ receipt: ManagedAssetPurgeReceipt,
        payload: Data,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
            INSERT INTO managed_asset_purge_receipts(
                purge_id, storage_object_id, purged_at_ms, deletion_method,
                prior_hash_algorithm, prior_hash_hex, prior_byte_size_decimal,
                data_classification, receipt_payload, receipt_sha256,
                receipt_byte_size
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                receipt.purgeID.uuidString.lowercased(),
                receipt.storageObjectID.canonicalString,
                receipt.purgedAt.millisecondsSinceUnixEpoch,
                receipt.deletionMethod.rawValue,
                receipt.priorContentHash.algorithm.encodedValue,
                receipt.priorContentHash.lowercaseHex,
                String(receipt.priorByteSize),
                receipt.dataClassification.encodedValue,
                payload,
                SQLitePayloadCodec.sha256(payload),
                payload.count
            ]
        )
    }

    private func purgeReceipt(
        storageObjectID: StorageObjectID,
        in db: Database
    ) throws -> ManagedAssetPurgeReceipt? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM managed_asset_purge_receipts WHERE storage_object_id = ?",
            arguments: [storageObjectID.canonicalString]
        ) else { return nil }
        return try decodePurgeReceipt(row: row)
    }

    private func decodePurgeReceipt(row: Row) throws -> ManagedAssetPurgeReceipt {
        let payload: Data = row["receipt_payload"]
        let digest: String = row["receipt_sha256"]
        guard SQLitePayloadCodec.sha256(payload) == digest,
              (row["receipt_byte_size"] as Int64) == Int64(payload.count)
        else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "A permanent-deletion receipt failed integrity validation."
            )
        }
        let receipt = try JSONDecoder().decode(ManagedAssetPurgeReceipt.self, from: payload)
        guard try SQLitePayloadCodec.canonicalData(receipt) == payload,
              row["purge_id"] == receipt.purgeID.uuidString.lowercased(),
              row["storage_object_id"] == receipt.storageObjectID.canonicalString,
              (row["purged_at_ms"] as Int64)
                  == receipt.purgedAt.millisecondsSinceUnixEpoch,
              row["deletion_method"] == receipt.deletionMethod.rawValue,
              row["prior_hash_algorithm"] == receipt.priorContentHash.algorithm.encodedValue,
              row["prior_hash_hex"] == receipt.priorContentHash.lowercaseHex,
              row["prior_byte_size_decimal"] == String(receipt.priorByteSize),
              row["data_classification"] == receipt.dataClassification.encodedValue
        else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "A permanent-deletion receipt index does not match its payload."
            )
        }
        return receipt
    }
}

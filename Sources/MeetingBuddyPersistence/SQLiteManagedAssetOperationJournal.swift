import CryptoKit
import Foundation
import GRDB
import MeetingBuddyApplication
import MeetingBuddyDomain

extension SQLitePersistenceStore {
    func beginManagedAssetOperation(_ intent: ManagedAssetOperationIntent) throws {
        let intentPayload = try operationPayload(intent)
        let event = try ManagedAssetOperationEventPayload(
            state: .intent,
            resultRecord: nil,
            failureCode: nil
        )
        let eventPayload = try operationPayload(event)
        try databasePool.write { db in
            if let existing = try managedAssetOperation(
                operationID: intent.operationID,
                in: db
            ) {
                guard existing.intent == intent else {
                    throw PersistenceContractError.managedAssetConflict(intent.storageObjectID)
                }
                return
            }
            try db.execute(
                sql: """
                INSERT INTO managed_asset_operations(
                    operation_id,
                    storage_object_id,
                    operation_kind,
                    state,
                    created_at_ms,
                    updated_at_ms,
                    intent_payload,
                    intent_sha256,
                    result_payload,
                    result_sha256,
                    failure_code
                ) VALUES (?, ?, ?, 'intent', ?, ?, ?, ?, NULL, NULL, NULL)
                """,
                arguments: [
                    intent.operationID.uuidString.lowercased(),
                    intent.storageObjectID.canonicalString,
                    intent.kind.rawValue,
                    intent.requestedAt.millisecondsSinceUnixEpoch,
                    intent.requestedAt.millisecondsSinceUnixEpoch,
                    intentPayload.data,
                    intentPayload.sha256
                ]
            )
            try insertManagedAssetOperationEvent(
                operationID: intent.operationID,
                sequence: 1,
                occurredAt: intent.requestedAt,
                payload: eventPayload,
                in: db
            )
        }
    }

    func markManagedAssetFilesystemApplied(
        operationID: UUID,
        resultRecord: ManagedAssetRecord,
        at timestamp: UTCInstant
    ) throws {
        try transitionManagedAssetOperation(
            operationID: operationID,
            to: .filesystemApplied,
            resultRecord: resultRecord,
            failureCode: nil,
            at: timestamp,
            allowedPreviousStates: [.intent]
        )
    }

    func completeManagedAssetOperation(
        operationID: UUID,
        at timestamp: UTCInstant
    ) throws {
        try transitionManagedAssetOperation(
            operationID: operationID,
            to: .completed,
            resultRecord: nil,
            failureCode: nil,
            at: timestamp,
            allowedPreviousStates: [.intent, .filesystemApplied, .repairRequired]
        )
    }

    func rollBackManagedAssetOperation(
        operationID: UUID,
        resultRecord: ManagedAssetRecord? = nil,
        at timestamp: UTCInstant
    ) throws {
        try transitionManagedAssetOperation(
            operationID: operationID,
            to: .rolledBack,
            resultRecord: resultRecord,
            failureCode: nil,
            at: timestamp,
            allowedPreviousStates: [.intent, .filesystemApplied, .repairRequired]
        )
    }

    func markManagedAssetOperationRepairRequired(
        operationID: UUID,
        resultRecord: ManagedAssetRecord?,
        failureCode: String,
        at timestamp: UTCInstant
    ) throws {
        try transitionManagedAssetOperation(
            operationID: operationID,
            to: .repairRequired,
            resultRecord: resultRecord,
            failureCode: failureCode,
            at: timestamp,
            allowedPreviousStates: [.intent, .filesystemApplied, .repairRequired]
        )
    }

    func unfinishedManagedAssetOperations(
        maximumOperations: UInt32
    ) throws -> ManagedAssetOperationScan {
        guard maximumOperations > 0, maximumOperations <= 4_096 else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "Managed-asset reconciliation requires a bounded operation count."
            )
        }
        return try databasePool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM managed_asset_operations
                WHERE state IN ('intent', 'filesystem_applied', 'repair_required')
                ORDER BY created_at_ms, operation_id
                LIMIT ?
                """,
                arguments: [Int64(maximumOperations) + 1]
            )
            return ManagedAssetOperationScan(
                entries: try rows.prefix(Int(maximumOperations)).map {
                    try decodeManagedAssetOperation(row: $0)
                },
                truncated: rows.count > Int(maximumOperations)
            )
        }
    }

    private func transitionManagedAssetOperation(
        operationID: UUID,
        to replacementState: ManagedAssetOperationState,
        resultRecord: ManagedAssetRecord?,
        failureCode: String?,
        at timestamp: UTCInstant,
        allowedPreviousStates: Set<ManagedAssetOperationState>
    ) throws {
        if let failureCode {
            guard !failureCode.isEmpty,
                  failureCode.utf8.count <= 96,
                  failureCode.utf8.allSatisfy({
                      ($0 >= 97 && $0 <= 122)
                          || ($0 >= 48 && $0 <= 57)
                          || $0 == 95
                  })
            else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "A recovery failure code must be a bounded lowercase identifier."
                )
            }
        }
        try databasePool.write { db in
            guard let current = try managedAssetOperation(operationID: operationID, in: db) else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "The managed-asset operation journal entry is missing."
                )
            }
            if current.state == replacementState {
                if let resultRecord {
                    guard current.resultRecord == resultRecord else {
                        throw PersistenceContractError.managedAssetConflict(
                            current.intent.storageObjectID
                        )
                    }
                }
                return
            }
            guard allowedPreviousStates.contains(current.state),
                  timestamp >= current.intent.requestedAt
            else {
                throw WorkspaceContractError.invalidStorageTransition(
                    "The managed-asset operation journal rejected a state transition."
                )
            }
            let nextResult = resultRecord ?? current.resultRecord
            let resultPayload = try nextResult.map(operationPayload)
            let event = try ManagedAssetOperationEventPayload(
                state: replacementState,
                resultRecord: nextResult,
                failureCode: failureCode
            )
            let eventPayload = try operationPayload(event)
            try db.execute(
                sql: """
                UPDATE managed_asset_operations
                SET state = ?,
                    updated_at_ms = ?,
                    result_payload = ?,
                    result_sha256 = ?,
                    failure_code = ?
                WHERE operation_id = ? AND state = ?
                """,
                arguments: [
                    replacementState.rawValue,
                    timestamp.millisecondsSinceUnixEpoch,
                    resultPayload?.data,
                    resultPayload?.sha256,
                    failureCode,
                    operationID.uuidString.lowercased(),
                    current.state.rawValue
                ]
            )
            guard db.changesCount == 1 else {
                throw WorkspaceContractError.invalidStorageTransition(
                    "The managed-asset operation changed concurrently."
                )
            }
            let sequence = try Int64.fetchOne(
                db,
                sql: """
                SELECT COALESCE(MAX(sequence), 0) + 1
                FROM managed_asset_operation_events
                WHERE operation_id = ?
                """,
                arguments: [operationID.uuidString.lowercased()]
            ) ?? 1
            try insertManagedAssetOperationEvent(
                operationID: operationID,
                sequence: sequence,
                occurredAt: timestamp,
                payload: eventPayload,
                in: db
            )
        }
    }

    private func managedAssetOperation(
        operationID: UUID,
        in db: Database
    ) throws -> ManagedAssetOperationEntry? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM managed_asset_operations WHERE operation_id = ?",
            arguments: [operationID.uuidString.lowercased()]
        ) else {
            return nil
        }
        return try decodeManagedAssetOperation(row: row)
    }

    private func decodeManagedAssetOperation(row: Row) throws -> ManagedAssetOperationEntry {
        let operationIDValue: String = row["operation_id"]
        let storageObjectIDValue: String = row["storage_object_id"]
        let kindValue: String = row["operation_kind"]
        let stateValue: String = row["state"]
        let intentData: Data = row["intent_payload"]
        let intentHash: String = row["intent_sha256"]
        guard operationDigest(intentData) == intentHash,
              let operationID = UUID(uuidString: operationIDValue),
              let kind = ManagedAssetOperationKind(rawValue: kindValue),
              let state = ManagedAssetOperationState(rawValue: stateValue)
        else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "A managed-asset operation journal row failed its index or digest check."
            )
        }
        let intent = try JSONDecoder().decode(ManagedAssetOperationIntent.self, from: intentData)
        guard intent.operationID == operationID,
              intent.operationID.uuidString.lowercased() == operationIDValue,
              intent.storageObjectID.canonicalString == storageObjectIDValue,
              intent.kind == kind,
              try operationPayload(intent).data == intentData
        else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "A managed-asset operation intent disagrees with its indexed row."
            )
        }
        let resultData: Data? = row["result_payload"]
        let resultHash: String? = row["result_sha256"]
        let resultRecord: ManagedAssetRecord?
        if let resultData {
            guard operationDigest(resultData) == resultHash else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "A managed-asset operation result failed its digest check."
                )
            }
            let decoded = try JSONDecoder().decode(ManagedAssetRecord.self, from: resultData)
            guard decoded.storageObjectID == intent.storageObjectID,
                  try operationPayload(decoded).data == resultData
            else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "A managed-asset operation result disagrees with its intent."
                )
            }
            resultRecord = decoded
        } else {
            guard resultHash == nil else {
                throw WorkspaceContractError.recoveryArtifactInvalid(
                    "A managed-asset operation has a digest without a result."
                )
            }
            resultRecord = nil
        }
        return ManagedAssetOperationEntry(
            intent: intent,
            state: state,
            resultRecord: resultRecord,
            failureCode: row["failure_code"]
        )
    }

    private func insertManagedAssetOperationEvent(
        operationID: UUID,
        sequence: Int64,
        occurredAt: UTCInstant,
        payload: OperationPayload,
        in db: Database
    ) throws {
        let event = try JSONDecoder().decode(
            ManagedAssetOperationEventPayload.self,
            from: payload.data
        )
        try db.execute(
            sql: """
            INSERT INTO managed_asset_operation_events(
                operation_id,
                sequence,
                state,
                occurred_at_ms,
                event_payload,
                event_sha256
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                operationID.uuidString.lowercased(),
                sequence,
                event.state.rawValue,
                occurredAt.millisecondsSinceUnixEpoch,
                payload.data,
                payload.sha256
            ]
        )
    }

    private func operationPayload<Value: Encodable>(_ value: Value) throws -> OperationPayload {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard !data.isEmpty, data.count <= 1_048_576 else {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "A managed-asset operation payload exceeded its bounded size."
            )
        }
        return OperationPayload(data: data, sha256: operationDigest(data))
    }

    private func operationDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct ManagedAssetOperationEventPayload: Codable {
    let state: ManagedAssetOperationState
    let resultRecord: ManagedAssetRecord?
    let failureCode: String?

    init(
        state: ManagedAssetOperationState,
        resultRecord: ManagedAssetRecord?,
        failureCode: String?
    ) throws {
        if let failureCode, failureCode.isEmpty {
            throw WorkspaceContractError.recoveryArtifactInvalid(
                "A managed-asset event failure code cannot be empty."
            )
        }
        self.state = state
        self.resultRecord = resultRecord
        self.failureCode = failureCode
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case resultRecord = "result_record"
        case failureCode = "failure_code"
    }
}

private struct OperationPayload {
    let data: Data
    let sha256: String
}

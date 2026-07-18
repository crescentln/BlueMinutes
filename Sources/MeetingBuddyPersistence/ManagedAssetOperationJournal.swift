import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

enum ManagedAssetOperationKind: String, Codable, Hashable, Sendable {
    case `import`
    case trash
    case restore
}

enum ManagedAssetOperationState: String, Codable, Hashable, Sendable {
    case intent
    case filesystemApplied = "filesystem_applied"
    case completed
    case rolledBack = "rolled_back"
    case repairRequired = "repair_required"

    var isUnfinished: Bool {
        self == .intent || self == .filesystemApplied || self == .repairRequired
    }
}

struct ManagedAssetImportPlan: Codable, Sendable, Equatable {
    let meetingID: MeetingID
    let storageObjectID: StorageObjectID
    let fileExtension: ManagedFileExtension?
    let createdAt: UTCInstant
    let dataClassification: DataClassification
    let retentionClass: RetentionClass

    init(
        meetingID: MeetingID,
        storageObjectID: StorageObjectID,
        fileExtension: ManagedFileExtension?,
        createdAt: UTCInstant,
        dataClassification: DataClassification,
        retentionClass: RetentionClass
    ) throws {
        guard dataClassification.isKnown, retentionClass.isKnown else {
            throw WorkspaceContractError.managedAssetMismatch(
                "A managed-asset import plan requires recognized storage policy values."
            )
        }
        self.meetingID = meetingID
        self.storageObjectID = storageObjectID
        self.fileExtension = fileExtension
        self.createdAt = createdAt
        self.dataClassification = dataClassification
        self.retentionClass = retentionClass
    }

    private enum CodingKeys: String, CodingKey {
        case meetingID = "meeting_id"
        case storageObjectID = "storage_object_id"
        case fileExtension = "file_extension"
        case createdAt = "created_at"
        case dataClassification = "data_classification"
        case retentionClass = "retention_class"
    }
}

struct ManagedAssetOperationIntent: Codable, Sendable, Equatable {
    let operationID: UUID
    let kind: ManagedAssetOperationKind
    let storageObjectID: StorageObjectID
    let requestedAt: UTCInstant
    let importPlan: ManagedAssetImportPlan?
    let beforeRecord: ManagedAssetRecord?
    let plannedRecord: ManagedAssetRecord?

    static func importing(
        operationID: UUID,
        plan: ManagedAssetImportPlan
    ) -> ManagedAssetOperationIntent {
        ManagedAssetOperationIntent(
            operationID: operationID,
            kind: .import,
            storageObjectID: plan.storageObjectID,
            requestedAt: plan.createdAt,
            importPlan: plan,
            beforeRecord: nil,
            plannedRecord: nil
        )
    }

    static func transitioning(
        operationID: UUID,
        kind: ManagedAssetOperationKind,
        requestedAt: UTCInstant,
        beforeRecord: ManagedAssetRecord,
        plannedRecord: ManagedAssetRecord
    ) throws -> ManagedAssetOperationIntent {
        let statesAreValid = switch kind {
        case .trash:
            beforeRecord.state == .active && plannedRecord.state == .trashed
        case .restore:
            beforeRecord.state == .trashed && plannedRecord.state == .active
        case .import:
            false
        }
        guard statesAreValid,
              beforeRecord.storageObjectID == plannedRecord.storageObjectID,
              beforeRecord.meetingID == plannedRecord.meetingID,
              beforeRecord.originalRelativePath == plannedRecord.originalRelativePath,
              beforeRecord.contentHash == plannedRecord.contentHash,
              beforeRecord.byteSize == plannedRecord.byteSize,
              beforeRecord.createdAt == plannedRecord.createdAt,
              beforeRecord.dataClassification == plannedRecord.dataClassification,
              beforeRecord.retentionClass == plannedRecord.retentionClass
        else {
            throw WorkspaceContractError.invalidStorageTransition(
                "A managed-asset operation intent is internally inconsistent."
            )
        }
        return ManagedAssetOperationIntent(
            operationID: operationID,
            kind: kind,
            storageObjectID: beforeRecord.storageObjectID,
            requestedAt: requestedAt,
            importPlan: nil,
            beforeRecord: beforeRecord,
            plannedRecord: plannedRecord
        )
    }

    private enum CodingKeys: String, CodingKey {
        case operationID = "operation_id"
        case kind
        case storageObjectID = "storage_object_id"
        case requestedAt = "requested_at"
        case importPlan = "import_plan"
        case beforeRecord = "before_record"
        case plannedRecord = "planned_record"
    }
}

struct ManagedAssetOperationEntry: Sendable {
    let intent: ManagedAssetOperationIntent
    let state: ManagedAssetOperationState
    let resultRecord: ManagedAssetRecord?
    let failureCode: String?
}

struct ManagedAssetOperationScan: Sendable {
    let entries: [ManagedAssetOperationEntry]
    let truncated: Bool
}

enum ManagedAssetFaultPoint: Equatable, Sendable {
    case afterIntent
    case afterFilesystemBeforeJournal
    case afterFilesystemJournal
    case afterMetadata
}

struct SimulatedManagedAssetProcessInterruption: Error, Sendable {}

import CryptoKit
import Foundation
import GRDB
import MeetingBuddyApplication
import MeetingBuddyDomain

enum SQLitePayloadCodec {
    static func canonicalData<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func managedAsset(from row: Row) throws -> ManagedAssetRecord {
        let storageObjectID = try StorageObjectID(validating: row["storage_object_id"] as String)
        let payload: Data = row["record_payload"]
        let digest: String = row["record_sha256"]
        guard sha256(payload) == digest else {
            throw PersistenceContractError.managedAssetConflict(storageObjectID)
        }
        let record = try JSONDecoder().decode(ManagedAssetRecord.self, from: payload)
        guard try canonicalData(record) == payload,
              record.storageObjectID == storageObjectID,
              row["meeting_id"] == record.meetingID.canonicalString,
              row["relative_path"] == record.relativePath.rawValue,
              row["original_relative_path"] == record.originalRelativePath.rawValue,
              row["content_hash_algorithm"] == record.contentHash.algorithm.encodedValue,
              row["content_hash_hex"] == record.contentHash.lowercaseHex,
              row["byte_size_decimal"] == String(record.byteSize),
              row["created_at_ms"] == record.createdAt.millisecondsSinceUnixEpoch,
              row["data_classification"] == record.dataClassification.encodedValue,
              row["retention_class"] == record.retentionClass.encodedValue,
              row["state"] == record.state.rawValue,
              (row["trashed_at_ms"] as Int64?) == record.trashedAt?.millisecondsSinceUnixEpoch
        else {
            throw PersistenceContractError.managedAssetConflict(storageObjectID)
        }
        return record
    }

}

enum SQLiteReferenceCodec {
    static func reference(
        objectTypeValue: String,
        logicalIDValue: String,
        revisionIDValue: String
    ) throws -> SemanticRevisionReference {
        let objectType = SemanticObjectType(encodedValue: objectTypeValue)
        let revisionID = try RevisionID(validating: revisionIDValue)
        switch objectType {
        case .sourceAsset:
            return try SemanticRevisionReference(
                logicalID: SourceAssetID(validating: logicalIDValue),
                revisionID: revisionID
            )
        case .evidenceRef:
            return try SemanticRevisionReference(
                logicalID: EvidenceID(validating: logicalIDValue),
                revisionID: revisionID
            )
        case .meetingProfile:
            return try SemanticRevisionReference(
                logicalID: MeetingID(validating: logicalIDValue),
                revisionID: revisionID
            )
        case .transcriptSegment:
            return try SemanticRevisionReference(
                logicalID: TranscriptSegmentID(validating: logicalIDValue),
                revisionID: revisionID
            )
        case .translationSegment:
            return try SemanticRevisionReference(
                logicalID: TranslationSegmentID(validating: logicalIDValue),
                revisionID: revisionID
            )
        case .actor:
            return try SemanticRevisionReference(
                logicalID: ActorID(validating: logicalIDValue),
                revisionID: revisionID
            )
        case .speakingCapacity:
            return try SemanticRevisionReference(
                logicalID: SpeakingCapacityID(validating: logicalIDValue),
                revisionID: revisionID
            )
        case .speakerAssignment:
            return try SemanticRevisionReference(
                logicalID: SpeakerAssignmentID(validating: logicalIDValue),
                revisionID: revisionID
            )
        case .participant:
            return try SemanticRevisionReference(
                logicalID: ParticipantID(validating: logicalIDValue),
                revisionID: revisionID
            )
        case .organization:
            return try SemanticRevisionReference(
                logicalID: OrganizationID(validating: logicalIDValue),
                revisionID: revisionID
            )
        case .issue:
            return try SemanticRevisionReference(
                logicalID: IssueID(validating: logicalIDValue),
                revisionID: revisionID
            )
        case .position:
            return try SemanticRevisionReference(
                logicalID: PositionID(validating: logicalIDValue),
                revisionID: revisionID
            )
        case .commitment:
            return try SemanticRevisionReference(
                logicalID: CommitmentID(validating: logicalIDValue),
                revisionID: revisionID
            )
        case .decision:
            return try SemanticRevisionReference(
                logicalID: DecisionID(validating: logicalIDValue),
                revisionID: revisionID
            )
        case .interventionCard:
            return try SemanticRevisionReference(
                logicalID: InterventionCardID(validating: logicalIDValue),
                revisionID: revisionID
            )
        case .delegationPositionCard:
            return try SemanticRevisionReference(
                logicalID: DelegationPositionCardID(validating: logicalIDValue),
                revisionID: revisionID
            )
        case .userConfirmedNote:
            return try SemanticRevisionReference(
                logicalID: UserConfirmedNoteID(validating: logicalIDValue),
                revisionID: revisionID
            )
        case .unrecognized:
            throw PersistenceContractError.unsupportedStoredObjectType(objectTypeValue)
        }
    }

    static func edge(from row: Row) throws -> DependencyEdge {
        try DependencyEdge(
            upstreamRevision: reference(
                objectTypeValue: row["upstream_object_type"],
                logicalIDValue: row["upstream_logical_id"],
                revisionIDValue: row["upstream_revision_id"]
            ),
            downstreamRevision: reference(
                objectTypeValue: row["downstream_object_type"],
                logicalIDValue: row["downstream_logical_id"],
                revisionIDValue: row["downstream_revision_id"]
            ),
            role: DependencyRole(encodedValue: row["role"])
        )
    }
}

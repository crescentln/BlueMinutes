import Foundation

enum IntelligenceRevisionSupport {
    static func hash<Tag: LogicalObjectIDScope, Content: Encodable>(
        revision: RevisionEnvelope<Tag>,
        content: Content
    ) throws -> ContentDigest {
        try SemanticHash.sha256(
            of: Projection(
                objectType: revision.objectType,
                schemaVersion: revision.schemaVersion,
                dataClassification: revision.dataClassification,
                inputRevisions: revision.inputRevisions,
                sourceAssetRevisions: revision.sourceAssetRevisions,
                evidenceRevisions: revision.evidenceRevisions,
                content: content
            )
        )
    }

    static func commonIssues<Tag: LogicalObjectIDScope>(
        revision: RevisionEnvelope<Tag>,
        expectedType: SemanticObjectType,
        reviewStatus: ReviewStatus,
        userConfirmed: Bool,
        calculatedHash: () throws -> ContentDigest,
        objectName: String
    ) -> [ValidationIssue] {
        var issues = revision.validationIssues()
        if revision.objectType != expectedType {
            issues.append(issue(.inconsistentValue, "revision.object_type", "\(objectName) requires the \(expectedType.encodedValue) object type."))
        }
        if revision.schemaVersion != .v1 {
            issues.append(issue(.unsupportedValue, "revision.schema_version", "\(objectName) supports schema version 1.0 only."))
        }
        issues.append(contentsOf: reviewConfirmationIssues(reviewStatus: reviewStatus, userConfirmed: userConfirmed))
        if userConfirmed, revision.createdBy != .user {
            issues.append(issue(.inconsistentValue, "revision.created_by", "User-confirmed intelligence must be created by the user."))
        }
        issues.append(
            contentsOf: semanticHashIssues(
                storedHash: revision.semanticContentHash,
                calculatedHash: calculatedHash,
                objectName: objectName
            )
        )
        return issues
    }

    static func exactInputIssues(
        _ reference: SemanticRevisionReference,
        expectedTypes: Set<SemanticObjectType>,
        revisionInputs: [SemanticRevisionReference],
        path: String,
        noun: String
    ) -> [ValidationIssue] {
        var issues = reference.validationIssues()
        if !expectedTypes.contains(reference.objectType) {
            issues.append(issue(.inconsistentValue, "\(path).object_type", "\(noun) has an incompatible object type."))
        }
        if !revisionInputs.contains(reference) {
            issues.append(issue(.missingRequiredValue, "revision.input_revisions", "The exact \(noun) must appear in input revisions."))
        }
        return issues
    }

    static func meetingInputIssues(
        meetingID: MeetingID,
        revisionInputs: [SemanticRevisionReference]
    ) -> [ValidationIssue] {
        let matches = revisionInputs.filter {
            $0.objectType == .meetingProfile
                && $0.logicalID.canonicalString == meetingID.canonicalString
        }
        guard matches.count == 1 else {
            return [
                issue(
                    .missingRequiredValue,
                    "revision.input_revisions",
                    "Intelligence must retain exactly one MeetingProfile revision for its meeting."
                )
            ]
        }
        return []
    }

    static func evidenceClosureIssues(
        claims: [EvidenceLinkedClaim],
        revisionEvidence: [SemanticRevisionReference],
        lifecycle: LifecycleStatus,
        createdBy: CreationActor,
        reviewStatus: ReviewStatus,
        userConfirmed: Bool
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let claimEvidence = Set(claims.flatMap(\.evidenceRevisions))
        if !claimEvidence.isSubset(of: Set(revisionEvidence)) {
            issues.append(issue(.missingRequiredValue, "revision.evidence_revisions", "Every claim evidence reference must appear in the revision envelope."))
        }
        if lifecycle == .published, claims.contains(where: { !$0.isPublishable }) {
            issues.append(issue(.missingRequiredValue, "claims", "Published intelligence cannot contain an unsupported material claim."))
        }
        if claims.contains(where: { $0.taxonomy == .userConfirmedConclusion }),
           !(createdBy == .user && reviewStatus == .confirmed && userConfirmed)
        {
            issues.append(issue(.inconsistentValue, "claims.taxonomy", "Only an explicitly confirmed user revision may contain a user-confirmed conclusion."))
        }
        return issues
    }

    static func issue(
        _ code: ValidationIssueCode,
        _ path: String,
        _ message: String
    ) -> ValidationIssue {
        ValidationIssue(code: code, path: path, message: message)
    }

    private struct Projection<Content: Encodable>: Encodable {
        let objectType: SemanticObjectType
        let schemaVersion: SchemaVersion
        let dataClassification: DataClassification
        let inputRevisions: [SemanticRevisionReference]
        let sourceAssetRevisions: [SemanticRevisionReference]
        let evidenceRevisions: [SemanticRevisionReference]
        let content: Content

        private enum CodingKeys: String, CodingKey {
            case objectType = "object_type"
            case schemaVersion = "schema_version"
            case dataClassification = "data_classification"
            case inputRevisions = "input_revisions"
            case sourceAssetRevisions = "source_asset_revisions"
            case evidenceRevisions = "evidence_revisions"
            case content
        }
    }
}

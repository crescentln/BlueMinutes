import Foundation
import Testing
@testable import MeetingBuddyDomain

@Suite
struct RevisionEnvelopeTests {
    @Test
    func validPublishedEnvelopeRequiresValidationTimestampAndSemanticHash() throws {
        let envelope = try TestFixtures.sourceEnvelope(
            lifecycleStatus: .published,
            validationState: .valid,
            publishedAt: TestFixtures.publishedAt,
            semanticContentHash: TestFixtures.semanticDigest
        )
        try envelope.validate()
    }

    @Test
    func publishedEnvelopeRejectsMissingPublicationRequirementsDeterministically() {
        let first = capturedValidationError {
            _ = try TestFixtures.sourceEnvelope(lifecycleStatus: .published)
        }
        let second = capturedValidationError {
            _ = try TestFixtures.sourceEnvelope(lifecycleStatus: .published)
        }

        #expect(first == second)
        #expect(first?.issues.map(\.code) == [.missingRequiredValue, .inconsistentValue, .missingRequiredValue])
    }

    @Test
    func envelopeRejectsSelfSupersedeAndDuplicateReferences() throws {
        let source = try SemanticRevisionReference(
            logicalID: TestFixtures.sourceAssetID,
            revisionID: TestFixtures.replacementSourceRevisionID
        )
        let error = capturedValidationError {
            _ = try TestFixtures.sourceEnvelope(
                supersedesRevisionID: TestFixtures.sourceRevisionID,
                inputRevisions: [source, source]
            )
        }

        #expect(error?.issues.map(\.code) == [.inconsistentValue, .duplicateValue])
    }

    @Test
    func envelopeRejectsSelfDependencyInEveryReferenceGroup() throws {
        let selfSource = try SemanticRevisionReference(
            logicalID: SourceAssetID(UUID(uuidString: "00000000-0000-0000-0000-000000000013")!),
            revisionID: TestFixtures.sourceRevisionID
        )
        let selfEvidence = try SemanticRevisionReference(
            logicalID: EvidenceID(UUID(uuidString: "00000000-0000-0000-0000-000000000014")!),
            revisionID: TestFixtures.sourceRevisionID
        )

        let inputError = capturedValidationError {
            _ = try TestFixtures.sourceEnvelope(inputRevisions: [selfSource])
        }
        let sourceError = capturedValidationError {
            _ = try RevisionEnvelope(
                logicalID: TestFixtures.sourceAssetID,
                revisionID: TestFixtures.sourceRevisionID,
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: TestFixtures.createdAt,
                createdBy: .application,
                sourceAssetRevisions: [selfSource],
                dataClassification: .internal
            )
        }
        let evidenceError = capturedValidationError {
            _ = try RevisionEnvelope(
                logicalID: TestFixtures.sourceAssetID,
                revisionID: TestFixtures.sourceRevisionID,
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: TestFixtures.createdAt,
                createdBy: .application,
                evidenceRevisions: [selfEvidence],
                dataClassification: .internal
            )
        }

        #expect(inputError?.issues.map(\.path) == ["input_revisions"])
        #expect(sourceError?.issues.map(\.path) == ["source_asset_revisions"])
        #expect(evidenceError?.issues.map(\.path) == ["evidence_revisions"])
    }

    @Test
    func decodedEnvelopeRejectsObjectTypeThatConflictsWithIDScope() throws {
        let canonical = try CanonicalJSON.encodeValidated(TestFixtures.sourceEnvelope())
        let mismatched = Data(
            String(decoding: canonical, as: UTF8.self)
                .replacingOccurrences(of: #""object_type":"source_asset""#, with: #""object_type":"evidence_ref""#)
                .utf8
        )

        #expect(throws: DomainValidationError.self) {
            try JSONDecoder().decode(RevisionEnvelope<SourceAssetIDTag>.self, from: mismatched)
        }
    }

    @Test
    func referenceSetsAreSortedForCanonicalEncoding() throws {
        let first = try SemanticRevisionReference(
            logicalID: SourceAssetID(UUID(uuidString: "10000000-0000-0000-0000-000000000001")!),
            revisionID: RevisionID(UUID(uuidString: "10000000-0000-0000-0000-000000000002")!)
        )
        let second = try SemanticRevisionReference(
            logicalID: SourceAssetID(UUID(uuidString: "20000000-0000-0000-0000-000000000001")!),
            revisionID: RevisionID(UUID(uuidString: "20000000-0000-0000-0000-000000000002")!)
        )
        let lhs = try TestFixtures.sourceEnvelope(inputRevisions: [second, first])
        let rhs = try TestFixtures.sourceEnvelope(inputRevisions: [first, second])
        let lhsData = try CanonicalJSON.encodeValidated(lhs)
        let rhsData = try CanonicalJSON.encodeValidated(rhs)

        #expect(lhs.inputRevisions == [first, second])
        #expect(lhsData == rhsData)
    }

    @Test
    func creatingReplacementLeavesPriorRevisionUnchanged() throws {
        let original = try TestFixtures.sourceEnvelope()
        let replacement = try TestFixtures.sourceEnvelope(
            revisionID: TestFixtures.replacementSourceRevisionID,
            supersedesRevisionID: original.revisionID
        )

        #expect(original.revisionID == TestFixtures.sourceRevisionID)
        #expect(original.supersedesRevisionID == nil)
        #expect(replacement.revisionID != original.revisionID)
        #expect(replacement.supersedesRevisionID == original.revisionID)
    }
}

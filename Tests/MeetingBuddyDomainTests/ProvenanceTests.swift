import Foundation
import Testing
@testable import MeetingBuddyDomain

@Suite
struct ProvenanceTests {
    @Test
    func completeProviderNeutralGenerationMetadataRoundTripsCanonically() throws {
        let metadata = try GenerationMetadata(
            provider: ProviderMetadata(
                providerIdentifier: "local-runtime",
                modelIdentifier: "meeting-model",
                modelVersion: "1.2.0",
                clientVersion: "3.0.0"
            ),
            promptModuleVersions: [
                VersionedComponent(identifier: "source-grounding", version: "2"),
                VersionedComponent(identifier: "diplomatic-rules", version: "1")
            ],
            outputSchemaVersion: .v1,
            templateVersion: "briefing-v1",
            generatedAt: TestFixtures.acquiredAt,
            privacyRoute: .localOnly
        )

        let canonical = try CanonicalJSON.encodeValidated(metadata)
        let decoded = try CanonicalJSON.decodeValidated(GenerationMetadata.self, from: canonical)

        #expect(decoded == metadata)
        #expect(decoded.promptModuleVersions.map(\.identifier) == [
            "diplomatic-rules",
            "source-grounding"
        ])
        #expect(
            String(decoding: canonical, as: UTF8.self)
                == #"{"generated_at":1699999999000,"output_schema_version":{"major":1,"minor":0},"privacy_route":"local_only","prompt_module_versions":[{"identifier":"diplomatic-rules","version":"1"},{"identifier":"source-grounding","version":"2"}],"provider":{"client_version":"3.0.0","model_identifier":"meeting-model","model_version":"1.2.0","provider_identifier":"local-runtime"},"template_version":"briefing-v1"}"#
        )
        #expect(!String(decoding: canonical, as: UTF8.self).contains("credential"))
    }

    @Test
    func revisionRequiresGenerationOutputSchemaToMatchEnvelope() throws {
        let metadata = try GenerationMetadata(
            provider: ProviderMetadata(
                providerIdentifier: "local-runtime",
                modelIdentifier: "meeting-model"
            ),
            promptModuleVersions: [
                VersionedComponent(identifier: "generator", version: "1")
            ],
            outputSchemaVersion: SchemaVersion(major: 2),
            templateVersion: "v1",
            generatedAt: TestFixtures.acquiredAt,
            privacyRoute: .localOnly
        )

        let error = capturedValidationError {
            _ = try RevisionEnvelope(
                logicalID: TestFixtures.sourceAssetID,
                revisionID: TestFixtures.sourceRevisionID,
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: TestFixtures.createdAt,
                createdBy: .provider,
                dataClassification: .internal,
                generationMetadata: metadata
            )
        }

        #expect(error?.issues.map(\.path) == ["generation_metadata.output_schema_version"])

        let missingMetadata = capturedValidationError {
            _ = try RevisionEnvelope(
                logicalID: TestFixtures.sourceAssetID,
                revisionID: TestFixtures.sourceRevisionID,
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: TestFixtures.createdAt,
                createdBy: .provider,
                dataClassification: .internal
            )
        }
        #expect(missingMetadata?.issues.map(\.path) == ["generation_metadata"])

        let futureMetadata = try GenerationMetadata(
            provider: metadata.provider,
            promptModuleVersions: metadata.promptModuleVersions,
            outputSchemaVersion: .v1,
            templateVersion: metadata.templateVersion,
            generatedAt: TestFixtures.publishedAt,
            privacyRoute: metadata.privacyRoute
        )
        let futureGeneration = capturedValidationError {
            _ = try RevisionEnvelope(
                logicalID: TestFixtures.sourceAssetID,
                revisionID: TestFixtures.sourceRevisionID,
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: TestFixtures.createdAt,
                createdBy: .provider,
                dataClassification: .internal,
                generationMetadata: futureMetadata
            )
        }
        #expect(futureGeneration?.issues.map(\.path) == ["generation_metadata.generated_at"])
    }

    @Test
    func provenanceRejectsPathsDuplicatesAndUnknownRoute() throws {
        #expect(throws: DomainValidationError.self) {
            try ProviderMetadata(
                providerIdentifier: "../provider",
                modelIdentifier: "model"
            )
        }
        #expect(throws: DomainValidationError.self) {
            try GenerationMetadata(
                provider: ProviderMetadata(
                    providerIdentifier: "provider",
                    modelIdentifier: "model"
                ),
                promptModuleVersions: [
                    VersionedComponent(identifier: "rules", version: "1"),
                    VersionedComponent(identifier: "rules", version: "2")
                ],
                outputSchemaVersion: .v1,
                templateVersion: "v1",
                generatedAt: TestFixtures.acquiredAt,
                privacyRoute: .localOnly
            )
        }

        let valid = try GenerationMetadata(
            provider: ProviderMetadata(
                providerIdentifier: "provider",
                modelIdentifier: "model"
            ),
            promptModuleVersions: [VersionedComponent(identifier: "rules", version: "1")],
            outputSchemaVersion: .v1,
            templateVersion: "v1",
            generatedAt: TestFixtures.acquiredAt,
            privacyRoute: .localOnly
        )
        let unknownRoute = Data(
            String(decoding: try CanonicalJSON.encode(valid), as: UTF8.self)
                .replacingOccurrences(of: #""privacy_route":"local_only""#, with: #""privacy_route":"future_route""#)
                .utf8
        )
        #expect(throws: DomainValidationError.self) {
            try JSONDecoder().decode(GenerationMetadata.self, from: unknownRoute)
        }

        let missingTemplate = Data(
            String(decoding: try CanonicalJSON.encode(valid), as: UTF8.self)
                .replacingOccurrences(of: #","template_version":"v1""#, with: "")
                .utf8
        )
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GenerationMetadata.self, from: missingTemplate)
        }
    }
}

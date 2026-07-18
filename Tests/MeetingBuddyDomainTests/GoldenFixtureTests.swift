import Foundation
import Testing
@testable import MeetingBuddyDomain

@Suite
struct GoldenFixtureTests {
    @Test
    func goldenCatalogContainsExactlyFiveUniqueCases() throws {
        let fixtures = try GoldenFixtureCatalog.all()
        let expected = Set([
            "ordinary_delegation_intervention",
            "reservation_or_qualification",
            "uncertain_speaker",
            "interpretation_versus_original_audio",
            "prepared_china_statement_versus_delivered"
        ])

        #expect(fixtures.count == 5)
        #expect(Set(fixtures.map(\.manifest.testCaseID)) == expected)
        #expect(Set(fixtures.map(\.manifest.testCaseVersion)) == ["1.0"])
    }

    @Test
    func goldenFixturesHaveExplicitSyntheticRightsMetadata() throws {
        for fixture in try GoldenFixtureCatalog.all() {
            let manifest = fixture.manifest
            #expect(manifest.sourceProvenance == .projectSynthetic)
            #expect(manifest.licensingStatus == .syntheticNoThirdPartyMaterial)
            #expect(manifest.spdxLicenseIdentifier == nil)
            #expect(manifest.repositoryReuseTerms == .unspecified)
            #expect(manifest.externalSources.isEmpty)
            #expect(!manifest.containsRealMeetingContent)
            #expect(!manifest.containsPersonalData)
            #expect(manifest.materialScope == "semantic_contract_only")
            #expect(manifest.humanDiplomaticReviewStatus == .notPerformed)
            #expect(manifest.idealBriefingSectionsStatus == "deferred_to_task_006b")
            #expect(manifest.scoringRubricVersion == "contract_input_v1")
        }
    }

    @Test
    func goldenContractGraphsValidateSerializeAndRoundTrip() throws {
        for fixture in try GoldenFixtureCatalog.all() {
            let graph = fixture.graph
            try roundTrip(graph.meeting)
            for source in graph.sourceAssets { try roundTrip(source) }
            for transcript in graph.transcripts { try roundTrip(transcript) }
            for translation in graph.translations { try roundTrip(translation) }
            for actor in graph.actors { try roundTrip(actor) }
            for capacity in graph.capacities { try roundTrip(capacity) }
            for assignment in graph.assignments { try roundTrip(assignment) }
            for evidence in graph.evidence { try roundTrip(evidence) }

            try InputContractGraphValidation.validate(
                meeting: graph.meeting,
                sourceAssets: graph.sourceAssets,
                actors: graph.actors
            )
            for actor in graph.actors {
                try InputContractGraphValidation.validate(actor: actor, affiliations: [])
            }
            for transcript in graph.transcripts {
                let source = try #require(
                    graph.sourceAssets.first {
                        (try? reference($0)) == transcript.sourceAssetRevision
                    }
                )
                try InputContractGraphValidation.validate(
                    transcript: transcript,
                    sourceAsset: source
                )
            }
            for translation in graph.translations {
                let transcript = try #require(
                    graph.transcripts.first {
                        (try? reference($0)) == translation.sourceSegmentRevision
                    }
                )
                try InputContractGraphValidation.validate(
                    translation: translation,
                    sourceTranscript: transcript
                )
            }
            for capacity in graph.capacities {
                try InputContractGraphValidation.validate(capacity: capacity, actors: graph.actors)
            }
            for assignment in graph.assignments {
                let transcripts = graph.transcripts.filter {
                    guard let exact = try? reference($0) else { return false }
                    return assignment.transcriptSegmentRevisions.contains(exact)
                }
                let actor = try #require(
                    graph.actors.first { (try? reference($0)) == assignment.actorRevision }
                )
                let capacity = try #require(
                    graph.capacities.first {
                        (try? reference($0)) == assignment.speakingCapacityRevision
                    }
                )
                let evidence = graph.evidence.filter {
                    guard let exact = try? reference($0) else { return false }
                    return assignment.evidenceRevisions.contains(exact)
                }
                try InputContractGraphValidation.validate(
                    assignment: assignment,
                    transcripts: transcripts,
                    actor: actor,
                    capacity: capacity,
                    evidence: evidence
                )
            }
        }
    }

    @Test
    func goldenReferencesResolveToExactContainedRevisions() throws {
        for fixture in try GoldenFixtureCatalog.all() {
            let graph = fixture.graph
            var allReferences: Set<SemanticRevisionReference> = [try reference(graph.meeting)]
            allReferences.formUnion(try graph.sourceAssets.map(reference))
            allReferences.formUnion(try graph.transcripts.map(reference))
            allReferences.formUnion(try graph.translations.map(reference))
            allReferences.formUnion(try graph.actors.map(reference))
            allReferences.formUnion(try graph.capacities.map(reference))
            allReferences.formUnion(try graph.assignments.map(reference))
            allReferences.formUnion(try graph.evidence.map(reference))

            let envelopes = [anyEnvelope(graph.meeting)]
                + graph.sourceAssets.map(anyEnvelope)
                + graph.transcripts.map(anyEnvelope)
                + graph.translations.map(anyEnvelope)
                + graph.actors.map(anyEnvelope)
                + graph.capacities.map(anyEnvelope)
                + graph.assignments.map(anyEnvelope)
                + graph.evidence.map(anyEnvelope)
            for envelope in envelopes {
                for required in envelope.input + envelope.sourceAssets + envelope.evidence {
                    #expect(allReferences.contains(required))
                }
            }
            for observation in fixture.manifest.expectedObservations
                + fixture.manifest.expectedReservations
            {
                #expect(!observation.evidenceRevisionIDs.isEmpty)
                for revisionID in observation.evidenceRevisionIDs {
                    #expect(graph.evidence.contains(where: { $0.revision.revisionID == revisionID }))
                }
            }
        }
    }

    @Test
    func goldenSourceDescriptorsDoNotClaimAcousticGroundTruth() throws {
        for fixture in try GoldenFixtureCatalog.all() {
            #expect(!fixture.manifest.containsMediaBytes)
            #expect(!fixture.manifest.acousticGroundTruth)
        }
    }

    @Test
    func reservationFixturePreservesEveryCondition() throws {
        let fixture = try #require(
            GoldenFixtureCatalog.all().first {
                $0.manifest.testCaseID == "reservation_or_qualification"
            }
        )
        let codes = Set(fixture.manifest.expectedReservations.map(\.code))

        #expect(codes == ["voluntary_participation_condition", "existing_resources_condition"])
        #expect(fixture.manifest.forbiddenClaims.contains(.unconditionalSupport))
        #expect(fixture.manifest.forbiddenClaims.contains(.droppedQualification))
        #expect(fixture.graph.transcripts.contains {
            $0.text.contains("participation remains voluntary")
                && $0.text.contains("existing resources")
        })
    }

    @Test
    func uncertainSpeakerRemainsUnconfirmedWithoutRepresentedCountry() throws {
        let fixture = try #require(
            GoldenFixtureCatalog.all().first { $0.manifest.testCaseID == "uncertain_speaker" }
        )
        let assignment = try #require(fixture.graph.assignments.first)
        let capacity = try #require(fixture.graph.capacities.first)
        let actor = try #require(fixture.graph.actors.first)

        #expect(assignment.certainty == .uncertain)
        #expect(assignment.reviewStatus == .needsReview)
        #expect(!assignment.userConfirmed)
        #expect(capacity.representationRelationships.isEmpty)
        #expect(capacity.meetingRole == .unidentified)
        if case .unidentifiedParticipant = actor.identity {
            #expect(Bool(true))
        } else {
            Issue.record("The uncertain-speaker fixture must use an unidentified Actor identity.")
        }
    }

    @Test
    func interpretationOriginalAndTranslationRemainDistinct() throws {
        let fixture = try #require(
            GoldenFixtureCatalog.all().first {
                $0.manifest.testCaseID == "interpretation_versus_original_audio"
            }
        )
        let original = try #require(
            fixture.graph.transcripts.first { $0.speechSourceKind == .originalSpeakerAudio }
        )
        let interpretation = try #require(
            fixture.graph.transcripts.first { $0.speechSourceKind == .simultaneousInterpretation }
        )
        let translation = try #require(fixture.graph.translations.first)

        #expect(original.revision.revisionID != interpretation.revision.revisionID)
        #expect(original.sourceAssetRevision != interpretation.sourceAssetRevision)
        #expect(original.isOriginalVerbatim)
        #expect(!interpretation.isOriginalVerbatim)
        #expect(!translation.isOriginalVerbatim)
        #expect(translation.sourceSegmentRevision == (try reference(original)))
        #expect(fixture.manifest.forbiddenClaims.contains(.interpretationAsOriginalVerbatim))
    }

    @Test
    func chinaFixtureRecordsOnlySyntheticTextualDifferences() throws {
        let fixture = try #require(
            GoldenFixtureCatalog.all().first {
                $0.manifest.testCaseID == "prepared_china_statement_versus_delivered"
            }
        )
        let bases = Set(fixture.manifest.expectedObservations.map(\.basis))

        #expect(fixture.manifest.title.lowercased().contains("synthetic"))
        #expect(!fixture.manifest.containsRealMeetingContent)
        #expect(bases.isSubset(of: [.directSourceText, .directTextualDifference]))
        #expect(fixture.manifest.forbiddenClaims.contains(.confirmedPolicyChange))
        #expect(fixture.manifest.forbiddenClaims.contains(.realWorldPositionAttribution))
        #expect(fixture.graph.meeting.title.contains("完全虚构"))
    }

    @Test
    func manifestsDeclareOnlyOwnedObjectCountsAndDirectEvidenceBases() throws {
        for fixture in try GoldenFixtureCatalog.all() {
            let graph = fixture.graph
            let actual: [SemanticObjectType: Int] = [
                .meetingProfile: 1,
                .sourceAsset: graph.sourceAssets.count,
                .transcriptSegment: graph.transcripts.count,
                .translationSegment: graph.translations.count,
                .actor: graph.actors.count,
                .speakingCapacity: graph.capacities.count,
                .speakerAssignment: graph.assignments.count,
                .evidenceRef: graph.evidence.count
            ]
            #expect(fixture.manifest.expectedSemanticObjectCounts.allSatisfy {
                actual[$0.objectType] == $0.count
            })
            #expect((fixture.manifest.expectedObservations + fixture.manifest.expectedReservations).allSatisfy {
                $0.basis == .directSourceText || $0.basis == .directTextualDifference
            })
            #expect(!fixture.manifest.forbiddenClaims.isEmpty)
            #expect(!fixture.manifest.knownFailurePatterns.isEmpty)
        }
    }

    private func roundTrip<Value: SemanticRevisionContract>(_ value: Value) throws {
        let data = try CanonicalJSON.encodeValidated(value)
        #expect(try CanonicalJSON.decodeValidated(Value.self, from: data) == value)
    }

    private func reference<Value: SemanticRevisionContract>(
        _ value: Value
    ) throws -> SemanticRevisionReference {
        try SemanticRevisionReference(
            logicalID: value.revision.logicalID,
            revisionID: value.revision.revisionID
        )
    }

    private struct AnyEnvelope {
        let input: [SemanticRevisionReference]
        let sourceAssets: [SemanticRevisionReference]
        let evidence: [SemanticRevisionReference]
    }

    private func anyEnvelope<Value: SemanticRevisionContract>(_ value: Value) -> AnyEnvelope {
        AnyEnvelope(
            input: value.revision.inputRevisions,
            sourceAssets: value.revision.sourceAssetRevisions,
            evidence: value.revision.evidenceRevisions
        )
    }
}

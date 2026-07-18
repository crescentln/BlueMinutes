import Foundation
import Testing
@testable import MeetingBuddyDomain

@Suite
struct ActorAndSpeakerV1Tests {
    @Test
    func allActorIdentityKindsRoundTripWithoutCountryConflation() throws {
        let identities: [ActorIdentity] = [
            .person(displayName: "Synthetic Person", personName: "Pat Example"),
            .country(displayName: "State of Example", countryCode: try CountryCode("XE")),
            .internationalOrganization(displayName: "Synthetic International Organization"),
            .formalGroup(displayName: "Synthetic Regional Group"),
            .unOrgan(displayName: "Synthetic UN Organ"),
            .unSecretariat(displayName: "Synthetic Secretariat Unit"),
            .unidentifiedParticipant(label: "Unidentified participant"),
            .other(displayName: "Other synthetic entity")
        ]

        for (offset, identity) in identities.enumerated() {
            let actor = try Task003BFixtures.actor(
                logicalID: Task003BFixtures.id(130 + offset * 2, ActorID.self),
                revisionID: Task003BFixtures.id(131 + offset * 2, RevisionID.self),
                identity: identity,
                reviewStatus: identity == .unidentifiedParticipant(label: "Unidentified participant")
                    ? .needsReview
                    : .unreviewed
            )
            let data = try CanonicalJSON.encodeValidated(actor)
            #expect(try CanonicalJSON.decodeValidated(ActorV1.self, from: data) == actor)
            if case .country = identity {
                #expect(actor.identity.countryCode != nil)
            } else {
                #expect(actor.identity.countryCode == nil)
            }
        }
    }

    @Test
    func capacityUsesExactActorRelationshipsAndRoundTrips() throws {
        let speaker = try Task003BFixtures.actor()
        let state = try Task003BFixtures.stateActor()
        let capacity = try Task003BFixtures.capacity(speaker: speaker, represented: state)

        try InputContractGraphValidation.validate(
            capacity: capacity,
            actors: [state, speaker]
        )
        let data = try CanonicalJSON.encodeValidated(capacity)
        #expect(try CanonicalJSON.decodeValidated(SpeakingCapacityV1.self, from: data) == capacity)
        #expect(capacity.representedEntityRevisions == [try Task003BFixtures.reference(state.actorID, state.revision.revisionID)])
        #expect(capacity.onBehalfOfEntityRevisions.isEmpty)
    }

    @Test
    func chairExpertAndSecretariatRolesNeedNoInventedCountry() throws {
        let speaker = try Task003BFixtures.actor(
            identity: .person(displayName: "Synthetic Chair", personName: "Chair Example")
        )
        let speakerReference = try Task003BFixtures.reference(speaker.actorID, speaker.revision.revisionID)
        for (offset, role) in [MeetingRole.chair, .expert, .observer, .secretariatOfficial].enumerated() {
            let capacity = try SpeakingCapacityV1(
                revision: Task003BFixtures.envelope(
                    logicalID: Task003BFixtures.id(150 + offset * 2, SpeakingCapacityID.self),
                    revisionID: Task003BFixtures.id(151 + offset * 2, RevisionID.self),
                    inputRevisions: [speakerReference]
                ),
                meetingID: Task003BFixtures.meetingID,
                speakerActorRevision: speakerReference,
                meetingRole: role,
                reviewStatus: .unreviewed,
                userConfirmed: false
            )
            try InputContractGraphValidation.validate(capacity: capacity, actors: [speaker])
            #expect(capacity.representationRelationships.isEmpty)
        }
    }

    @Test
    func uncertainSpeakerRemainsNeedsReviewAndUnconfirmed() throws {
        let transcript = try Task003BFixtures.transcript()
        let actor = try Task003BFixtures.unidentifiedActor()
        let capacity = try Task003BFixtures.capacity(
            logicalID: Task003BFixtures.uncertainCapacityID,
            revisionID: Task003BFixtures.uncertainCapacityRevisionID,
            speaker: actor,
            role: .unidentified,
            reviewStatus: .needsReview
        )
        let evidence = try Task003BFixtures.evidenceForTranscript(transcript: transcript)
        let assignment = try Task003BFixtures.assignment(
            transcript: transcript,
            actor: actor,
            capacity: capacity,
            evidence: evidence,
            certainty: .uncertain,
            reviewStatus: .needsReview
        )

        #expect(!assignment.userConfirmed)
        #expect(assignment.certainty == .uncertain)
        #expect(assignment.reviewStatus == .needsReview)
        try InputContractGraphValidation.validate(
            assignment: assignment,
            transcripts: [transcript],
            actor: actor,
            capacity: capacity,
            evidence: [evidence]
        )
        let data = try CanonicalJSON.encodeValidated(assignment)
        #expect(try CanonicalJSON.decodeValidated(SpeakerAssignmentV1.self, from: data) == assignment)
    }

    @Test
    func uncertainAssignmentCannotBeConfirmedByConfidenceOrFlag() throws {
        #expect(throws: DomainValidationError.self) {
            _ = try Task003BFixtures.assignment(
                certainty: .uncertain,
                reviewStatus: .confirmed,
                userConfirmed: true,
                createdBy: .user
            )
        }
    }

    @Test
    func confirmedAssignmentRequiresExplicitUserCreatedRevision() throws {
        let confirmed = try Task003BFixtures.assignment(
            certainty: .confirmed,
            reviewStatus: .confirmed,
            userConfirmed: true,
            createdBy: .user
        )
        try confirmed.validate()

        #expect(throws: DomainValidationError.self) {
            _ = try Task003BFixtures.assignment(
                certainty: .confirmed,
                reviewStatus: .confirmed,
                userConfirmed: true,
                createdBy: .application
            )
        }
    }

    @Test
    func assignmentGraphRejectsActorCapacityMismatch() throws {
        let transcript = try Task003BFixtures.transcript()
        let assignedActor = try Task003BFixtures.actor()
        let otherActor = try Task003BFixtures.actor(
            logicalID: Task003BFixtures.id(160, ActorID.self),
            revisionID: Task003BFixtures.id(161, RevisionID.self),
            identity: .person(displayName: "Other Synthetic Person", personName: "Other Example")
        )
        let capacity = try Task003BFixtures.capacity(speaker: otherActor)
        let evidence = try Task003BFixtures.evidenceForTranscript(transcript: transcript)
        let assignment = try Task003BFixtures.assignment(
            transcript: transcript,
            actor: assignedActor,
            capacity: capacity,
            evidence: evidence
        )

        #expect(throws: DomainValidationError.self) {
            try InputContractGraphValidation.validate(
                assignment: assignment,
                transcripts: [transcript],
                actor: assignedActor,
                capacity: capacity,
                evidence: [evidence]
            )
        }
    }

    @Test
    func actorCapacityAndAssignmentHashesAreRepeatable() throws {
        let actor = try Task003BFixtures.actor()
        let capacity = try Task003BFixtures.capacity(speaker: actor)
        let assignment = try Task003BFixtures.assignment(actor: actor, capacity: capacity)

        #expect(try actor.calculatedSemanticContentHash() == actor.calculatedSemanticContentHash())
        #expect(try capacity.calculatedSemanticContentHash() == capacity.calculatedSemanticContentHash())
        #expect(try assignment.calculatedSemanticContentHash() == assignment.calculatedSemanticContentHash())
    }

    @Test
    func directDecodersRejectUnsupportedActorAndSpeakerSemantics() throws {
        let actorJSON = String(
            decoding: try CanonicalJSON.encode(Task003BFixtures.actor()),
            as: UTF8.self
        )
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ActorV1.self,
                from: Data(
                    actorJSON
                        .replacingOccurrences(of: #""kind":"person""#, with: #""kind":"future_actor""#)
                        .utf8
                )
            )
        }

        let capacityJSON = String(
            decoding: try CanonicalJSON.encode(Task003BFixtures.capacity()),
            as: UTF8.self
        )
        #expect(throws: DomainValidationError.self) {
            try JSONDecoder().decode(
                SpeakingCapacityV1.self,
                from: Data(
                    capacityJSON
                        .replacingOccurrences(of: #""meeting_role":"delegate""#, with: #""meeting_role":"future_role""#)
                        .utf8
                )
            )
        }

        let assignmentJSON = String(
            decoding: try CanonicalJSON.encode(Task003BFixtures.assignment()),
            as: UTF8.self
        )
        #expect(throws: DomainValidationError.self) {
            try JSONDecoder().decode(
                SpeakerAssignmentV1.self,
                from: Data(
                    assignmentJSON
                        .replacingOccurrences(of: #""certainty":"probable""#, with: #""certainty":"future_certainty""#)
                        .utf8
                )
            )
        }
    }
}

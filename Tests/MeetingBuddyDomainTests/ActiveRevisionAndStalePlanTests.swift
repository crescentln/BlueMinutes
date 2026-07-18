import Foundation
import Testing
@testable import MeetingBuddyDomain

@Suite
struct ActiveRevisionAndStalePlanTests {
    @Test
    func explicitPointerSelectsOnePublishedRevisionWithoutInferringLatest() throws {
        let first = try publishedMeeting(revisionID: Task003BFixtures.meetingRevisionID)
        let second = try publishedMeeting(
            revisionID: Task003BFixtures.replacementMeetingRevisionID,
            supersedesRevisionID: first.revision.revisionID
        )
        let firstSelection = try ActivePublishedRevisionSelection(
            logicalID: first.meetingID,
            revisionID: first.revision.revisionID
        )
        let secondSelection = try ActivePublishedRevisionSelection(
            logicalID: second.meetingID,
            revisionID: second.revision.revisionID
        )

        #expect(try ActivePublishedRevisionSelector.select(firstSelection, from: [second, first]) == first)
        #expect(try ActivePublishedRevisionSelector.select(secondSelection, from: [first, second]) == second)
        #expect(first.revision.lifecycleStatus == .published)
        #expect(second.revision.lifecycleStatus == .published)
    }

    @Test
    func activeSelectionRejectsDraftMissingAndDuplicateCandidates() throws {
        let draft = try Task003BFixtures.meetingProfile()
        let selection = try ActivePublishedRevisionSelection(
            logicalID: draft.meetingID,
            revisionID: draft.revision.revisionID
        )
        #expect(throws: DomainValidationError.self) {
            try ActivePublishedRevisionSelector.select(selection, from: [draft])
        }
        #expect(throws: DomainValidationError.self) {
            try ActivePublishedRevisionSelector.select(selection, from: [MeetingProfileV1]())
        }

        let published = try publishedMeeting(revisionID: draft.revision.revisionID)
        #expect(throws: DomainValidationError.self) {
            try ActivePublishedRevisionSelector.select(selection, from: [published, published])
        }
    }

    @Test
    func activePointerCanReactivateAnOlderPublishedRevision() throws {
        let old = try publishedMeeting(revisionID: Task003BFixtures.meetingRevisionID)
        let newer = try publishedMeeting(
            revisionID: Task003BFixtures.replacementMeetingRevisionID,
            supersedesRevisionID: old.revision.revisionID
        )
        let oldSelection = try ActivePublishedRevisionSelection(
            logicalID: old.meetingID,
            revisionID: old.revision.revisionID
        )
        let newSelection = try ActivePublishedRevisionSelection(
            logicalID: newer.meetingID,
            revisionID: newer.revision.revisionID
        )
        let reactivation = try ActivePublishedRevisionChange(
            previous: newSelection,
            replacement: oldSelection
        )

        try reactivation.validate()
        #expect(!reactivation.isNoOp)
        #expect(try ActivePublishedRevisionSelector.select(oldSelection, from: [old, newer]) == old)
    }

    @Test
    func dependencyEdgesIncludeAllEnvelopeReferenceRoles() throws {
        let source = try TestFixtures.sourceReference()
        let evidence = try Task003BFixtures.reference(
            TestFixtures.evidenceID,
            TestFixtures.evidenceRevisionID
        )
        let envelope: RevisionEnvelope<TranscriptSegmentIDTag> = try Task003BFixtures.envelope(
            logicalID: Task003BFixtures.transcriptID,
            revisionID: Task003BFixtures.transcriptRevisionID,
            inputRevisions: [source],
            sourceAssetRevisions: [source],
            evidenceRevisions: [evidence]
        )
        let edges = try DependencyEdge.from(downstream: envelope)

        #expect(edges.count == 3)
        #expect(Set(edges.map(\.role)) == [.input, .sourceAsset, .evidence])
    }

    @Test
    func stalePlannerTraversesChainAndDiamondOnceInStableOrder() throws {
        let change = try meetingChange()
        let old = try #require(change.previous)
        let transcript = try Task003BFixtures.reference(
            Task003BFixtures.transcriptID,
            Task003BFixtures.transcriptRevisionID
        )
        let actor = try Task003BFixtures.reference(
            Task003BFixtures.actorID,
            Task003BFixtures.actorRevisionID
        )
        let assignment = try Task003BFixtures.reference(
            Task003BFixtures.assignmentID,
            Task003BFixtures.assignmentRevisionID
        )
        let unrelatedSource = try TestFixtures.sourceReference()
        let unrelatedEvidence = try Task003BFixtures.reference(
            TestFixtures.evidenceID,
            TestFixtures.evidenceRevisionID
        )
        let edges = try [
            DependencyEdge(upstreamRevision: actor, downstreamRevision: assignment, role: .input),
            DependencyEdge(upstreamRevision: old, downstreamRevision: transcript, role: .input),
            DependencyEdge(upstreamRevision: transcript, downstreamRevision: assignment, role: .input),
            DependencyEdge(upstreamRevision: old, downstreamRevision: actor, role: .input),
            DependencyEdge(upstreamRevision: unrelatedSource, downstreamRevision: unrelatedEvidence, role: .evidence)
        ]
        let policy = try RevisionHandlingPolicy(revision: assignment, action: .recompute)
        let first = try DeterministicStalePlanner.plan(
            for: change,
            dependencyEdges: edges,
            handlingPolicies: [policy]
        )
        let second = try DeterministicStalePlanner.plan(
            for: change,
            dependencyEdges: edges.reversed(),
            handlingPolicies: [policy]
        )

        #expect(first == second)
        #expect(first.marks.map(\.affectedRevision) == [actor, transcript, assignment])
        #expect(first.marks.map(\.minimumDependencyDepth) == [1, 1, 2])
        #expect(first.marks.last?.action == .recompute)
        #expect(!first.marks.contains(where: { $0.affectedRevision == unrelatedEvidence }))
    }

    @Test
    func stalePlannerNoOpAndInitialPublicationProduceEmptyPlan() throws {
        let selection: ActivePublishedRevisionSelection<MeetingIDTag> = try ActivePublishedRevisionSelection(
            logicalID: Task003BFixtures.meetingID,
            revisionID: Task003BFixtures.meetingRevisionID
        )
        let noOp = try ActivePublishedRevisionChange(previous: selection, replacement: selection)
        let initial = try ActivePublishedRevisionChange(
            previous: Optional<ActivePublishedRevisionSelection<MeetingIDTag>>.none,
            replacement: selection
        )

        #expect(try DeterministicStalePlanner.plan(for: noOp, dependencyEdges: []).marks.isEmpty)
        #expect(try DeterministicStalePlanner.plan(for: initial, dependencyEdges: []).marks.isEmpty)
    }

    @Test
    func stalePlannerRejectsCyclesDuplicatesAndIndirectReplacementDependencies() throws {
        let change = try meetingChange()
        let old = try #require(change.previous)
        let transcript = try Task003BFixtures.reference(
            Task003BFixtures.transcriptID,
            Task003BFixtures.transcriptRevisionID
        )
        let first = try DependencyEdge(upstreamRevision: old, downstreamRevision: transcript, role: .input)
        let cycle = try DependencyEdge(upstreamRevision: transcript, downstreamRevision: old, role: .input)
        let optionalInvalidation = try InvalidationReason.activeReplacement(change)
        let invalidation = try #require(optionalInvalidation)

        #expect(throws: DomainValidationError.self) {
            _ = try StaleReason(invalidation: invalidation, dependencyPath: [first, cycle])
        }
        #expect(throws: DomainValidationError.self) {
            try DeterministicStalePlanner.plan(for: change, dependencyEdges: [first, cycle])
        }
        #expect(throws: DomainValidationError.self) {
            try DeterministicStalePlanner.plan(for: change, dependencyEdges: [first, first])
        }

        let replacementEdge = try DependencyEdge(
            upstreamRevision: old,
            downstreamRevision: change.replacement,
            role: .input
        )
        let lineagePlan = try DeterministicStalePlanner.plan(
            for: change,
            dependencyEdges: [replacementEdge]
        )
        #expect(lineagePlan.marks.isEmpty)

        let indirectReplacementEdge = try DependencyEdge(
            upstreamRevision: transcript,
            downstreamRevision: change.replacement,
            role: .input
        )
        #expect(throws: DomainValidationError.self) {
            try DeterministicStalePlanner.plan(
                for: change,
                dependencyEdges: [first, indirectReplacementEdge]
            )
        }
    }

    @Test
    func replacementAndStalePlanningLeavePriorRevisionUnchanged() throws {
        let original = try publishedMeeting(revisionID: Task003BFixtures.meetingRevisionID)
        let snapshot = try CanonicalJSON.encodeValidated(original)
        let change = try meetingChange()
        _ = try DeterministicStalePlanner.plan(for: change, dependencyEdges: [])

        #expect(try CanonicalJSON.encodeValidated(original) == snapshot)
        #expect(original.revision.supersedesRevisionID == nil)
    }

    @Test
    func directDecodersRejectInvalidStalePlanningPayloads() throws {
        let change = try meetingChange()
        let old = try #require(change.previous)
        let transcript = try Task003BFixtures.reference(
            Task003BFixtures.transcriptID,
            Task003BFixtures.transcriptRevisionID
        )
        let edge = try DependencyEdge(
            upstreamRevision: old,
            downstreamRevision: transcript,
            role: .input
        )
        let validPlan = try DeterministicStalePlanner.plan(
            for: change,
            dependencyEdges: [edge]
        )
        let validMark = try #require(validPlan.marks.first)
        let validPolicy = try RevisionHandlingPolicy(
            revision: transcript,
            action: .recompute
        )

        #expect(throws: DomainValidationError.self) {
            let data = try mutatedJSONData(from: validPolicy) { object in
                object["action"] = "future_action"
            }
            _ = try JSONDecoder().decode(RevisionHandlingPolicy.self, from: data)
        }
        #expect(throws: DomainValidationError.self) {
            let data = try mutatedJSONData(from: validMark.reason) { object in
                object["dependency_path"] = []
            }
            _ = try JSONDecoder().decode(StaleReason.self, from: data)
        }
        #expect(throws: DomainValidationError.self) {
            let data = try mutatedJSONData(from: validMark) { object in
                object["affected_revision"] = try JSONSerialization.jsonObject(
                    with: CanonicalJSON.encode(change.replacement)
                )
            }
            _ = try JSONDecoder().decode(StaleMark.self, from: data)
        }
        #expect(throws: DomainValidationError.self) {
            let data = try mutatedJSONData(from: validPlan) { object in
                object.removeValue(forKey: "invalidation")
            }
            _ = try JSONDecoder().decode(StalePlan.self, from: data)
        }
    }

    @Test
    func activeAndStalePlanningContractsRoundTripCanonically() throws {
        let change = try meetingChange()
        let old = try #require(change.previous)
        let transcript = try Task003BFixtures.reference(
            Task003BFixtures.transcriptID,
            Task003BFixtures.transcriptRevisionID
        )
        let edge = try DependencyEdge(
            upstreamRevision: old,
            downstreamRevision: transcript,
            role: .sourceAsset
        )
        let policy = try RevisionHandlingPolicy(
            revision: transcript,
            action: .preserveAndReview
        )
        let plan = try DeterministicStalePlanner.plan(
            for: change,
            dependencyEdges: [edge],
            handlingPolicies: [policy]
        )
        let selection: ActivePublishedRevisionSelection<MeetingIDTag> = try ActivePublishedRevisionSelection(
            logicalID: Task003BFixtures.meetingID,
            revisionID: Task003BFixtures.replacementMeetingRevisionID
        )

        #expect(try roundTrip(selection) == selection)
        #expect(try roundTrip(change) == change)
        #expect(try roundTrip(edge) == edge)
        #expect(try roundTrip(policy) == policy)
        #expect(try roundTrip(plan) == plan)
    }

    private func publishedMeeting(
        revisionID: RevisionID,
        supersedesRevisionID: RevisionID? = nil
    ) throws -> MeetingProfileV1 {
        let draftEnvelope = try Task003BFixtures.meetingEnvelope(
            revisionID: revisionID,
            supersedesRevisionID: supersedesRevisionID
        )
        let draft = try Task003BFixtures.meetingProfile(revision: draftEnvelope)
        let publishedEnvelope = try Task003BFixtures.meetingEnvelope(
            revisionID: revisionID,
            lifecycleStatus: .published,
            validationState: .valid,
            publishedAt: TestFixtures.publishedAt,
            supersedesRevisionID: supersedesRevisionID,
            semanticContentHash: draft.calculatedSemanticContentHash()
        )
        return try Task003BFixtures.meetingProfile(revision: publishedEnvelope)
    }

    private func meetingChange() throws -> ActivePublishedRevisionChange {
        let old: ActivePublishedRevisionSelection<MeetingIDTag> = try ActivePublishedRevisionSelection(
            logicalID: Task003BFixtures.meetingID,
            revisionID: Task003BFixtures.meetingRevisionID
        )
        let replacement: ActivePublishedRevisionSelection<MeetingIDTag> = try ActivePublishedRevisionSelection(
            logicalID: Task003BFixtures.meetingID,
            revisionID: Task003BFixtures.replacementMeetingRevisionID
        )
        return try ActivePublishedRevisionChange(previous: old, replacement: replacement)
    }

    private func mutatedJSONData<T: Encodable>(
        from value: T,
        mutate: (inout [String: Any]) throws -> Void
    ) throws -> Data {
        let data = try CanonicalJSON.encode(value)
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        try mutate(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func roundTrip<T: Codable & Equatable & DomainValidatable>(_ value: T) throws -> T {
        let data = try CanonicalJSON.encodeValidated(value)
        return try CanonicalJSON.decodeValidated(T.self, from: data)
    }
}

import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import Testing

@Suite
struct TranscriptSourceContractTests {
    @Test
    func providerContractReportsAndFetchesFactsWithoutMakingASRDecisions() async throws {
        let snapshot = try transcriptSnapshot(timed: false)
        let availability = try transcriptAvailability(for: snapshot)
        let provider = SyntheticTranscriptSourceProvider(
            availability: availability,
            snapshot: snapshot
        )
        let probed = try await provider.probe(transcriptContext())
        let fetched = try await provider.fetch(snapshot.reference)
        let refreshed = try await provider.refresh(snapshot.reference)

        #expect(probed == availability)
        #expect(fetched == snapshot)
        #expect(refreshed == snapshot)
        #expect(await provider.callCount == 3)
    }

    @Test
    func untimedTranscriptIsTruthfulButCannotSatisfyCanonicalAudioCoverage() throws {
        let snapshot = try transcriptSnapshot(timed: false)
        let candidate = try TranscriptResolutionCandidate(
            availability: transcriptAvailability(for: snapshot),
            snapshot: snapshot
        )

        #expect(snapshot.segments.allSatisfy { $0.timeRange == nil })
        #expect(!snapshot.hasCompleteTiming)
        #expect(!candidate.canSatisfyCanonicalAudioCoverage)
    }

    @Test
    func unknownSourceFactsFailClosed() {
        #expect(throws: DomainValidationError.self) {
            _ = try TranscriptSourceSnapshot(
                reference: transcriptReference(),
                authority: .unrecognized("future_authority"),
                completeness: .complete,
                language: LanguageTag("en"),
                segments: [TranscriptSourceSegment(sequence: 1, text: "Synthetic text.")],
                contentDigest: transcriptDigest("c"),
                dataClassification: .internal,
                fetchedAt: transcriptInstant(10)
            )
        }
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                TranscriptSourceSnapshot.self,
                from: Data(#"{"reference":{}}"#.utf8)
            )
        }
    }

    @Test
    func resolverDecisionCannotSkipASRWithoutCanonicalCoverageProof() throws {
        let snapshot = try transcriptSnapshot(timed: false)
        let input = try resolutionInput(snapshot: snapshot)

        #expect(throws: DomainValidationError.self) {
            _ = try TranscriptResolutionDecision(
                selectedPrimarySource: snapshot.reference,
                shouldRunLocalASR: false,
                reason: TranscriptResolutionReason(
                    code: "external-source-selected",
                    displayText: "Synthetic source selected."
                ),
                consideredAlternatives: [snapshot.reference],
                inputSnapshot: input
            )
        }
    }

    @Test
    func resolverDecisionRetainsExactInputAndMaySkipOnlyWithBoundProof() throws {
        let snapshot = try transcriptSnapshot(timed: true)
        let input = try resolutionInput(snapshot: snapshot, withCoverageProof: true)
        let decision = try TranscriptResolutionDecision(
            selectedPrimarySource: snapshot.reference,
            authoritativeReference: snapshot.reference,
            shouldRunLocalASR: false,
            reason: TranscriptResolutionReason(
                code: "verified-canonical-coverage",
                displayText: "Verified external source covers the canonical audio."
            ),
            consideredAlternatives: [snapshot.reference],
            inputSnapshot: input
        )

        #expect(snapshot.hasCompleteTiming)
        #expect(input.candidates[0].canSatisfyCanonicalAudioCoverage)
        #expect(decision.selectedPrimarySource == snapshot.reference)
        #expect(decision.authoritativeReference == snapshot.reference)
        #expect(decision.consideredAlternatives == [snapshot.reference])
        #expect(decision.inputSnapshot == input)
        #expect(decision.reason.code == "verified-canonical-coverage")
    }

    @Test
    func candidateOrderIsCanonicalAndDoesNotEncodeAuthorityPriority() throws {
        let firstSnapshot = try transcriptSnapshot(
            providerIdentifier: "z-provider",
            authority: .official,
            timed: false
        )
        let secondSnapshot = try transcriptSnapshot(
            providerIdentifier: "a-provider",
            authority: .unverified,
            timed: false
        )
        let first = try TranscriptResolutionCandidate(
            availability: transcriptAvailability(for: firstSnapshot),
            snapshot: firstSnapshot
        )
        let second = try TranscriptResolutionCandidate(
            availability: transcriptAvailability(for: secondSnapshot),
            snapshot: secondSnapshot
        )
        let policy = try transcriptPolicy()
        let context = try transcriptContext()
        let capturedAt = transcriptInstant(30)
        let forward = try TranscriptResolutionInputSnapshot(
            context: context,
            policy: policy,
            candidates: [first, second],
            capturedAt: capturedAt
        )
        let reverse = try TranscriptResolutionInputSnapshot(
            context: context,
            policy: policy,
            candidates: [second, first],
            capturedAt: capturedAt
        )

        #expect(forward.candidates == reverse.candidates)
        #expect(forward.contentHash == reverse.contentHash)
        #expect(forward.candidates.first?.availability.reference.providerIdentifier == "a-provider")
        #expect(forward.candidates.first?.availability.authority == .unverified)
    }
}

private actor SyntheticTranscriptSourceProvider: TranscriptSourceProviding {
    let availability: TranscriptSourceAvailability
    let snapshot: TranscriptSourceSnapshot
    private(set) var callCount = 0

    init(
        availability: TranscriptSourceAvailability,
        snapshot: TranscriptSourceSnapshot
    ) {
        self.availability = availability
        self.snapshot = snapshot
    }

    func probe(_ context: TranscriptSourceContext) async throws
        -> TranscriptSourceAvailability
    {
        _ = context
        callCount += 1
        return availability
    }

    func fetch(_ reference: TranscriptSourceReference) async throws
        -> TranscriptSourceSnapshot
    {
        #expect(reference == snapshot.reference)
        callCount += 1
        return snapshot
    }

    func refresh(_ reference: TranscriptSourceReference) async throws
        -> TranscriptSourceSnapshot
    {
        #expect(reference == snapshot.reference)
        callCount += 1
        return snapshot
    }
}

private func resolutionInput(
    snapshot: TranscriptSourceSnapshot,
    withCoverageProof: Bool = false
) throws -> TranscriptResolutionInputSnapshot {
    try TranscriptResolutionInputSnapshot(
        context: transcriptContext(),
        policy: transcriptPolicy(),
        candidates: [
            TranscriptResolutionCandidate(
                availability: transcriptAvailability(for: snapshot),
                snapshot: snapshot,
                applicationAudioCoverageBinding: withCoverageProof
                    ? transcriptCoverageBinding()
                    : nil
            )
        ],
        capturedAt: transcriptInstant(20)
    )
}

private func transcriptPolicy() throws -> TranscriptResolutionPolicySnapshot {
    try TranscriptResolutionPolicySnapshot(
        policyVersion: VersionedComponent(
            identifier: "synthetic-transcript-resolution-policy",
            version: "1"
        ),
        localASRAllowed: true,
        localASRAvailable: true,
        externalSourceUseAllowed: true
    )
}

private func transcriptContext() throws -> TranscriptSourceContext {
    try TranscriptSourceContext(
        meetingRevision: SemanticRevisionReference(
            logicalID: transcriptID(1, MeetingID.self),
            revisionID: transcriptID(2, RevisionID.self)
        ),
        requestedLanguage: LanguageTag("en"),
        canonicalAudioSourceRevision: transcriptSourceRevision(),
        dataClassification: .internal
    )
}

private func transcriptAvailability(
    for snapshot: TranscriptSourceSnapshot
) throws -> TranscriptSourceAvailability {
    try TranscriptSourceAvailability(
        reference: snapshot.reference,
        status: .available,
        authority: snapshot.authority,
        completeness: snapshot.completeness,
        checkedAt: transcriptInstant(8)
    )
}

private func transcriptSnapshot(
    providerIdentifier: String = "synthetic-provider",
    authority: SourceAuthority = .official,
    timed: Bool
) throws -> TranscriptSourceSnapshot {
    let reference = try transcriptReference(providerIdentifier: providerIdentifier)
    let ranges = [
        try MediaTimeRange(startMilliseconds: 0, endMilliseconds: 1_000),
        try MediaTimeRange(startMilliseconds: 1_000, endMilliseconds: 2_000)
    ]
    let segments = try ["First synthetic segment.", "Second synthetic segment."]
        .enumerated()
        .map { index, text in
            try TranscriptSourceSegment(
                sequence: UInt64(index + 1),
                text: text,
                timeRange: timed ? ranges[index] : nil
            )
        }
    return try TranscriptSourceSnapshot(
        reference: reference,
        authority: authority,
        completeness: .complete,
        language: LanguageTag("en"),
        segments: segments,
        contentDigest: transcriptDigest("e"),
        dataClassification: .internal,
        fetchedAt: transcriptInstant(9)
    )
}

private func transcriptCoverageBinding() throws -> TranscriptAudioCoverageBinding {
    try TranscriptAudioCoverageBinding(
        coverageManifestID: transcriptID(10, TranscriptCoverageManifestID.self),
        coverageManifestHash: transcriptDigest("d"),
        canonicalSourceRevision: transcriptSourceRevision(),
        verifiedCompleteFrameCoverage: true,
        verifier: VersionedComponent(
            identifier: "synthetic-coverage-verifier",
            version: "1"
        )
    )
}

private func transcriptReference(
    providerIdentifier: String = "synthetic-provider"
) throws -> TranscriptSourceReference {
    try TranscriptSourceReference(
        providerIdentifier: providerIdentifier,
        sourceIdentifier: "source-1",
        sourceVersionIdentifier: "version-1",
        sourceKind: .officialTranscript,
        externalReference: HTTPSURL("https://example.invalid/transcript")
    )
}

private func transcriptSourceRevision() throws -> SemanticRevisionReference {
    try SemanticRevisionReference(
        logicalID: transcriptID(20, SourceAssetID.self),
        revisionID: transcriptID(21, RevisionID.self)
    )
}

private func transcriptID<Tag>(_ suffix: Int, _: StableID<Tag>.Type) -> StableID<Tag> {
    StableID(
        UUID(
            uuidString: String(
                format: "10000000-0000-0000-0000-%012d",
                suffix
            )
        )!
    )
}

private func transcriptInstant(_ offset: Int64) -> UTCInstant {
    try! UTCInstant(millisecondsSinceUnixEpoch: 1_900_000_100_000 + offset)
}

private func transcriptDigest(_ character: Character) -> ContentDigest {
    try! ContentDigest(
        algorithm: .sha256,
        lowercaseHex: String(repeating: character, count: 64)
    )
}

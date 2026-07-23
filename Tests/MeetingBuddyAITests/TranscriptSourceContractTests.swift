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
    func leadingTimingGapCannotSatisfyCanonicalAudioCoverage() throws {
        let snapshot = try transcriptSnapshot(
            timed: true,
            timeRanges: [
                MediaTimeRange(startMilliseconds: 1, endMilliseconds: 1_000),
                MediaTimeRange(startMilliseconds: 1_000, endMilliseconds: 2_000)
            ]
        )

        #expect(!snapshot.hasCompleteTiming)
        #expect(throws: DomainValidationError.self) {
            _ = try TranscriptResolutionCandidate(
                availability: transcriptAvailability(for: snapshot),
                snapshot: snapshot,
                applicationAudioCoverageBinding: transcriptCoverageBinding(for: snapshot)
            )
        }
    }

    @Test
    func interiorTimingGapCannotSatisfyCanonicalAudioCoverage() throws {
        let snapshot = try transcriptSnapshot(
            timed: true,
            timeRanges: [
                MediaTimeRange(startMilliseconds: 0, endMilliseconds: 1_000),
                MediaTimeRange(startMilliseconds: 1_001, endMilliseconds: 2_000)
            ]
        )

        #expect(!snapshot.hasCompleteTiming)
        #expect(throws: DomainValidationError.self) {
            _ = try TranscriptResolutionCandidate(
                availability: transcriptAvailability(for: snapshot),
                snapshot: snapshot,
                applicationAudioCoverageBinding: transcriptCoverageBinding(for: snapshot)
            )
        }
    }

    @Test
    func untimedSegmentCannotHideTimedOverlapOrReordering() throws {
        let invalidTimedRanges = [
            [
                try MediaTimeRange(startMilliseconds: 0, endMilliseconds: 2_000),
                try MediaTimeRange(startMilliseconds: 1_000, endMilliseconds: 3_000)
            ],
            [
                try MediaTimeRange(startMilliseconds: 2_000, endMilliseconds: 3_000),
                try MediaTimeRange(startMilliseconds: 0, endMilliseconds: 1_000)
            ]
        ]

        for timedRanges in invalidTimedRanges {
            #expect(throws: DomainValidationError.self) {
                _ = try transcriptSnapshotWithUntimedMiddleSegment(
                    firstTimedRange: timedRanges[0],
                    finalTimedRange: timedRanges[1]
                )
            }
        }
    }

    @Test
    func untimedSegmentMaySeparateChronologicalNonoverlappingTiming() throws {
        let snapshot = try transcriptSnapshotWithUntimedMiddleSegment(
            firstTimedRange: MediaTimeRange(
                startMilliseconds: 0,
                endMilliseconds: 1_000
            ),
            finalTimedRange: MediaTimeRange(
                startMilliseconds: 1_000,
                endMilliseconds: 2_000
            )
        )

        #expect(snapshot.segments.count == 3)
        #expect(snapshot.segments[1].timeRange == nil)
        #expect(!snapshot.hasCompleteTiming)
    }

    @Test
    func externalPolicyDenialRejectsExternalSelectionsWhileLocalASRRuns() throws {
        let snapshot = try transcriptSnapshot(timed: false)
        let input = try resolutionInput(
            snapshot: snapshot,
            policy: transcriptPolicy(externalSourceUseAllowed: false)
        )
        let reason = try TranscriptResolutionReason(
            code: "local-asr-required",
            displayText: "External transcript source use is not authorized."
        )

        #expect(throws: DomainValidationError.self) {
            _ = try TranscriptResolutionDecision(
                selectedPrimarySource: snapshot.reference,
                shouldRunLocalASR: true,
                reason: reason,
                consideredAlternatives: [snapshot.reference],
                inputSnapshot: input
            )
        }
        #expect(throws: DomainValidationError.self) {
            _ = try TranscriptResolutionDecision(
                selectedPrimarySource: nil,
                authoritativeReference: snapshot.reference,
                shouldRunLocalASR: true,
                reason: reason,
                consideredAlternatives: [snapshot.reference],
                inputSnapshot: input
            )
        }

        let decision = try TranscriptResolutionDecision(
            selectedPrimarySource: nil,
            authoritativeReference: nil,
            shouldRunLocalASR: true,
            reason: reason,
            consideredAlternatives: [snapshot.reference],
            inputSnapshot: input
        )
        #expect(decision.shouldRunLocalASR)
        #expect(decision.selectedPrimarySource == nil)
        #expect(decision.authoritativeReference == nil)
    }

    @Test
    func coverageBindingRejectsDifferentSnapshotReference() throws {
        let snapshot = try transcriptSnapshot(timed: true)
        let differentReference = try transcriptReference(
            providerIdentifier: "different-provider"
        )

        #expect(throws: DomainValidationError.self) {
            _ = try TranscriptResolutionCandidate(
                availability: transcriptAvailability(for: snapshot),
                snapshot: snapshot,
                applicationAudioCoverageBinding: transcriptCoverageBinding(
                    for: snapshot,
                    transcriptSourceReference: differentReference
                )
            )
        }
    }

    @Test
    func coverageBindingRejectsDifferentSnapshotContentDigest() throws {
        let snapshot = try transcriptSnapshot(timed: true)

        #expect(throws: DomainValidationError.self) {
            _ = try TranscriptResolutionCandidate(
                availability: transcriptAvailability(for: snapshot),
                snapshot: snapshot,
                applicationAudioCoverageBinding: transcriptCoverageBinding(
                    for: snapshot,
                    transcriptSourceContentDigest: transcriptDigest("f")
                )
            )
        }
    }

    @Test
    func coverageBindingRejectsDifferentCanonicalSnapshot() throws {
        let original = try transcriptSnapshot(timed: true)
        let changedTiming = try transcriptSnapshot(
            timed: true,
            timeRanges: [
                MediaTimeRange(startMilliseconds: 0, endMilliseconds: 900),
                MediaTimeRange(startMilliseconds: 900, endMilliseconds: 2_000)
            ]
        )
        let changedText = try transcriptSnapshot(
            timed: true,
            segmentTexts: [
                "Changed synthetic segment.",
                "Second synthetic segment."
            ]
        )
        let binding = try transcriptCoverageBinding(for: original)

        for differentSnapshot in [changedTiming, changedText] {
            #expect(differentSnapshot.reference == original.reference)
            #expect(differentSnapshot.contentDigest == original.contentDigest)
            #expect(try differentSnapshot.calculatedSnapshotHash()
                != original.calculatedSnapshotHash())
            #expect(throws: DomainValidationError.self) {
                _ = try TranscriptResolutionCandidate(
                    availability: transcriptAvailability(for: differentSnapshot),
                    snapshot: differentSnapshot,
                    applicationAudioCoverageBinding: binding
                )
            }
        }
    }

    @Test
    func coverageBindingRequiresFetchedSnapshot() throws {
        let snapshot = try transcriptSnapshot(timed: true)

        #expect(throws: DomainValidationError.self) {
            _ = try TranscriptResolutionCandidate(
                availability: transcriptAvailability(for: snapshot),
                applicationAudioCoverageBinding: transcriptCoverageBinding(for: snapshot)
            )
        }
    }

    @Test
    func legacyUnboundCoverageBindingFailsDecoding() throws {
        let snapshot = try transcriptSnapshot(timed: true)
        let binding = try transcriptCoverageBinding(for: snapshot)
        let encoded = try JSONEncoder().encode(binding)
        #expect(
            try JSONDecoder().decode(
                TranscriptAudioCoverageBinding.self,
                from: encoded
            ) == binding
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        for missingKey in [
            "transcript_source_reference",
            "transcript_source_content_digest",
            "transcript_source_snapshot_hash"
        ] {
            var legacyObject = object
            legacyObject.removeValue(forKey: missingKey)
            let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)

            #expect(throws: DecodingError.self) {
                _ = try JSONDecoder().decode(
                    TranscriptAudioCoverageBinding.self,
                    from: legacyData
                )
            }
        }
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
    withCoverageProof: Bool = false,
    policy: TranscriptResolutionPolicySnapshot? = nil
) throws -> TranscriptResolutionInputSnapshot {
    try TranscriptResolutionInputSnapshot(
        context: transcriptContext(),
        policy: policy ?? transcriptPolicy(),
        candidates: [
            TranscriptResolutionCandidate(
                availability: transcriptAvailability(for: snapshot),
                snapshot: snapshot,
                applicationAudioCoverageBinding: withCoverageProof
                    ? transcriptCoverageBinding(for: snapshot)
                    : nil
            )
        ],
        capturedAt: transcriptInstant(20)
    )
}

private func transcriptPolicy(
    externalSourceUseAllowed: Bool = true
) throws -> TranscriptResolutionPolicySnapshot {
    try TranscriptResolutionPolicySnapshot(
        policyVersion: VersionedComponent(
            identifier: "synthetic-transcript-resolution-policy",
            version: "1"
        ),
        localASRAllowed: true,
        localASRAvailable: true,
        externalSourceUseAllowed: externalSourceUseAllowed
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
    timed: Bool,
    timeRanges: [MediaTimeRange]? = nil,
    segmentTexts: [String] = [
        "First synthetic segment.",
        "Second synthetic segment."
    ]
) throws -> TranscriptSourceSnapshot {
    let reference = try transcriptReference(providerIdentifier: providerIdentifier)
    let ranges = try timeRanges ?? [
        try MediaTimeRange(startMilliseconds: 0, endMilliseconds: 1_000),
        try MediaTimeRange(startMilliseconds: 1_000, endMilliseconds: 2_000)
    ]
    let segments = try segmentTexts
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

private func transcriptSnapshotWithUntimedMiddleSegment(
    firstTimedRange: MediaTimeRange,
    finalTimedRange: MediaTimeRange
) throws -> TranscriptSourceSnapshot {
    try TranscriptSourceSnapshot(
        reference: transcriptReference(),
        authority: .official,
        completeness: .complete,
        language: LanguageTag("en"),
        segments: [
            TranscriptSourceSegment(
                sequence: 1,
                text: "First timed synthetic segment.",
                timeRange: firstTimedRange
            ),
            TranscriptSourceSegment(
                sequence: 2,
                text: "Untimed synthetic segment."
            ),
            TranscriptSourceSegment(
                sequence: 3,
                text: "Final timed synthetic segment.",
                timeRange: finalTimedRange
            )
        ],
        contentDigest: transcriptDigest("e"),
        dataClassification: .internal,
        fetchedAt: transcriptInstant(9)
    )
}

private func transcriptCoverageBinding(
    for snapshot: TranscriptSourceSnapshot,
    transcriptSourceReference: TranscriptSourceReference? = nil,
    transcriptSourceContentDigest: ContentDigest? = nil,
    transcriptSourceSnapshotHash: ContentDigest? = nil
) throws -> TranscriptAudioCoverageBinding {
    try TranscriptAudioCoverageBinding(
        coverageManifestID: transcriptID(10, TranscriptCoverageManifestID.self),
        coverageManifestHash: transcriptDigest("d"),
        canonicalSourceRevision: transcriptSourceRevision(),
        transcriptSourceReference: transcriptSourceReference ?? snapshot.reference,
        transcriptSourceContentDigest:
            transcriptSourceContentDigest ?? snapshot.contentDigest,
        transcriptSourceSnapshotHash:
            try transcriptSourceSnapshotHash ?? snapshot.calculatedSnapshotHash(),
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

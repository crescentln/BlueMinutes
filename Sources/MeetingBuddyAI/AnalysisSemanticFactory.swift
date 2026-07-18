import CryptoKit
import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public struct AnalysisResolvedUnit: Sendable {
    public let meeting: MeetingProfileV1
    public let transcript: TranscriptSegmentV1
    public let translation: TranslationSegmentV1?
    public let speakerAssignment: SpeakerAssignmentV1
    public let speakerActor: ActorV1
    public let speakingCapacity: SpeakingCapacityV1
    public let representedActor: ActorV1
    public let knownRecipientActors: [ActorV1]

    public init(
        meeting: MeetingProfileV1,
        transcript: TranscriptSegmentV1,
        translation: TranslationSegmentV1? = nil,
        speakerAssignment: SpeakerAssignmentV1,
        speakerActor: ActorV1,
        speakingCapacity: SpeakingCapacityV1,
        representedActor: ActorV1,
        knownRecipientActors: [ActorV1] = []
    ) throws {
        try meeting.validate()
        try transcript.validate()
        if let translation { try translation.validate() }
        try speakerAssignment.validate()
        try speakerActor.validate()
        try speakingCapacity.validate()
        try representedActor.validate()
        for actor in knownRecipientActors { try actor.validate() }
        let transcriptReference = try Self.reference(transcript)
        let actorReference = try Self.reference(speakerActor)
        let capacityReference = try Self.reference(speakingCapacity)
        let representedReference = try Self.reference(representedActor)
        let representedRelationships = speakingCapacity.representationRelationships.map(
            \.entityRevision
        )
        guard transcript.meetingID == meeting.meetingID,
              speakingCapacity.meetingID == meeting.meetingID,
              speakerAssignment.meetingID == meeting.meetingID,
              speakerAssignment.transcriptSegmentRevisions.contains(transcriptReference),
              speakerAssignment.actorRevision == actorReference,
              speakerAssignment.speakingCapacityRevision == capacityReference,
              speakingCapacity.speakerActorRevision == actorReference,
              representedReference == actorReference
                || representedRelationships.contains(representedReference),
              translation.map({
                  $0.meetingID == meeting.meetingID
                      && $0.sourceSegmentRevision == transcriptReference
              }) ?? true
        else {
            throw AIProviderContractError.invalidRequest(
                "The resolved analysis unit has inconsistent speaker, capacity, representation, or meeting inputs."
            )
        }
        self.meeting = meeting
        self.transcript = transcript
        self.translation = translation
        self.speakerAssignment = speakerAssignment
        self.speakerActor = speakerActor
        self.speakingCapacity = speakingCapacity
        self.representedActor = representedActor
        self.knownRecipientActors = knownRecipientActors
    }

    private static func reference<Object: SemanticRevisionContract>(
        _ value: Object
    ) throws -> SemanticRevisionReference {
        try SemanticRevisionReference(
            logicalID: value.revision.logicalID,
            revisionID: value.revision.revisionID
        )
    }
}

public struct AnalysisUnitObjects: Sendable {
    public let evidence: [EvidenceRefV1]
    public let participant: ParticipantV1
    public let organization: OrganizationV1?
    public let issue: IssueV1
    public let position: PositionV1
    public let commitment: CommitmentV1?
    public let decision: DecisionV1?
    public let interventionCard: InterventionCardV1

    public var outputReferences: [SemanticRevisionReference] {
        get throws {
            var references = try [
                AnalysisSemanticFactory.reference(participant),
                AnalysisSemanticFactory.reference(issue),
                AnalysisSemanticFactory.reference(position),
                AnalysisSemanticFactory.reference(interventionCard)
            ]
            if let organization {
                references.append(try AnalysisSemanticFactory.reference(organization))
            }
            if let commitment {
                references.append(try AnalysisSemanticFactory.reference(commitment))
            }
            if let decision {
                references.append(try AnalysisSemanticFactory.reference(decision))
            }
            return references.sorted()
        }
    }
}

public enum AnalysisSemanticFactory {
    public static func correctedPosition(
        prior: PositionV1,
        newRevisionID: RevisionID = RevisionID(UUID()),
        positionType: PositionType,
        statement: String,
        reservations: [String],
        conditions: [String],
        changedAt: UTCInstant
    ) throws -> PositionV1 {
        try prior.validate()
        guard prior.revision.lifecycleStatus == .published,
              prior.revision.validationState == .valid,
              positionType.isKnown
        else {
            throw AIProviderContractError.invalidRequest(
                "A position correction requires a valid published prior revision and known type."
            )
        }
        let priorReference = try reference(prior)
        let evidence = prior.revision.evidenceRevisions
        let confidence = try ConfidenceScore(millionths: 1_000_000)
        let correctedStatement = try claim(
            statement,
            taxonomy: .userConfirmedConclusion,
            support: .supported,
            evidence: evidence,
            confidence: confidence
        )
        let correctedReservations = try reservations.map {
            try claim(
                $0,
                taxonomy: .userConfirmedConclusion,
                support: .supported,
                evidence: evidence,
                confidence: confidence
            )
        }
        let correctedConditions = try conditions.map {
            try claim(
                $0,
                taxonomy: .userConfirmedConclusion,
                support: .supported,
                evidence: evidence,
                confidence: confidence
            )
        }
        let inputs = Array(Set(prior.revision.inputRevisions + [priorReference])).sorted()
        let draft = try PositionV1(
            revision: RevisionEnvelope(
                logicalID: prior.positionID,
                revisionID: newRevisionID,
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: changedAt,
                createdBy: .user,
                supersedesRevisionID: prior.revision.revisionID,
                inputRevisions: inputs,
                sourceAssetRevisions: prior.revision.sourceAssetRevisions,
                evidenceRevisions: evidence,
                dataClassification: prior.revision.dataClassification
            ),
            meetingID: prior.meetingID,
            actorRevision: prior.actorRevision,
            representedEntityRevision: prior.representedEntityRevision,
            speakingCapacityRevision: prior.speakingCapacityRevision,
            issueRevision: prior.issueRevision,
            positionType: positionType,
            statement: correctedStatement,
            reservations: correctedReservations,
            conditions: correctedConditions,
            effectiveTimeRange: prior.effectiveTimeRange,
            comparisonState: .insufficientEvidence,
            reviewStatus: .confirmed,
            userConfirmed: true
        )
        return try PositionV1(
            revision: publishedEnvelope(
                draft.revision,
                hash: try draft.calculatedSemanticContentHash(),
                at: changedAt
            ),
            meetingID: draft.meetingID,
            actorRevision: draft.actorRevision,
            representedEntityRevision: draft.representedEntityRevision,
            speakingCapacityRevision: draft.speakingCapacityRevision,
            issueRevision: draft.issueRevision,
            positionType: draft.positionType,
            statement: draft.statement,
            reservations: draft.reservations,
            conditions: draft.conditions,
            effectiveTimeRange: draft.effectiveTimeRange,
            comparisonState: draft.comparisonState,
            reviewStatus: draft.reviewStatus,
            userConfirmed: draft.userConfirmed
        )
    }

    public static func makeUnit(
        candidate: AnalysisOutputCandidate,
        resolved: AnalysisResolvedUnit,
        provider: ProviderMetadata,
        promptModules: [VersionedComponent] = DiplomaticAnalysisPrompt.modules,
        sharedParticipant: ParticipantV1? = nil,
        sharedOrganization: OrganizationV1? = nil,
        sharedIssue: IssueV1? = nil,
        createdAt: UTCInstant
    ) throws -> AnalysisUnitObjects {
        guard candidate.substantive,
              let interventionType = candidate.interventionType,
              let issueTitle = candidate.issueTitle,
              let positionType = candidate.positionType,
              let positionStatement = candidate.positionStatement,
              candidate.nonSubstantiveReasonCode == nil
        else {
            throw AIProviderContractError.invalidResponse(
                "Only a validated substantive candidate can create semantic objects."
            )
        }
        let meetingReference = try reference(resolved.meeting)
        let transcriptReference = try reference(resolved.transcript)
        let translationReference = try resolved.translation.map(reference)
        let assignmentReference = try reference(resolved.speakerAssignment)
        let actorReference = try reference(resolved.speakerActor)
        let capacityReference = try reference(resolved.speakingCapacity)
        let representedActorReference = try reference(resolved.representedActor)
        let baseInputs = [
            meetingReference,
            transcriptReference,
            assignmentReference,
            actorReference,
            capacityReference,
            representedActorReference
        ] + [translationReference].compactMap { $0 }
        let classification = DataClassification.mostRestrictive(
            [
                resolved.meeting.revision.dataClassification,
                resolved.transcript.revision.dataClassification,
                resolved.translation?.revision.dataClassification,
                resolved.speakerAssignment.revision.dataClassification,
                resolved.speakerActor.revision.dataClassification,
                resolved.speakingCapacity.revision.dataClassification,
                resolved.representedActor.revision.dataClassification
            ].compactMap { $0 }
        ) ?? .restricted
        let candidateDigest = try digest(candidate)
        let seed = [
            "task006a-v1",
            resolved.transcript.revision.revisionID.canonicalString,
            candidateDigest.lowercaseHex
        ].joined(separator: ":")
        let generation = try GenerationMetadata(
            provider: provider,
            promptModuleVersions: promptModules,
            outputSchemaVersion: .v1,
            templateVersion: "task006a-analysis-v1",
            generatedAt: createdAt,
            privacyRoute: .localOnly
        )
        let evidence = try evidenceChunks(
            transcript: resolved.transcript,
            seed: seed,
            classification: classification,
            createdAt: createdAt
        )
        let evidenceReferences = try evidence.map(reference)
        let support: EvidenceSupportStatus = resolved.speakerAssignment.certainty == .confirmed
            ? .supported
            : .uncertain

        let organization = try sharedOrganization ?? makeOrganizationIfNeeded(
            actor: resolved.representedActor,
            evidence: evidenceReferences,
            inputs: baseInputs,
            classification: classification,
            generation: generation,
            seed: seed,
            confidence: candidate.confidence,
            createdAt: createdAt
        )
        let organizationReference = try organization.map(reference)
        let participant = try sharedParticipant ?? makeParticipant(
            actor: resolved.speakerActor,
            capacity: resolved.speakingCapacity,
            meetingID: resolved.meeting.meetingID,
            organizationReference: organizationReference,
            evidence: evidenceReferences,
            inputs: baseInputs,
            classification: classification,
            generation: generation,
            seed: seed,
            confidence: candidate.confidence,
            createdAt: createdAt
        )
        let participantReference = try reference(participant)
        let representedEntityReference = organizationReference ?? participantReference
        let titleClaim = try claim(
            issueTitle,
            taxonomy: .meetingBuddyExtraction,
            support: support,
            evidence: evidenceReferences,
            confidence: candidate.confidence
        )
        let issue = try sharedIssue ?? makeIssue(
            meetingID: resolved.meeting.meetingID,
            title: titleClaim,
            evidence: evidenceReferences,
            inputs: baseInputs,
            classification: classification,
            generation: generation,
            seed: seed,
            createdAt: createdAt
        )
        let issueReference = try reference(issue)
        let positionClaim = try claim(
            positionStatement,
            taxonomy: .delegationClaim,
            support: support,
            evidence: evidenceReferences,
            confidence: candidate.confidence
        )
        let reservationClaims = try candidate.reservations.map {
            try claim(
                $0,
                taxonomy: .delegationClaim,
                support: support,
                evidence: evidenceReferences,
                confidence: candidate.confidence
            )
        }
        let conditionClaims = try candidate.conditions.map {
            try claim(
                $0,
                taxonomy: .delegationClaim,
                support: support,
                evidence: evidenceReferences,
                confidence: candidate.confidence
            )
        }
        let position = try makePosition(
            resolved: resolved,
            representedEntity: representedEntityReference,
            issue: issueReference,
            positionType: positionType,
            statement: positionClaim,
            reservations: reservationClaims,
            conditions: conditionClaims,
            evidence: evidenceReferences,
            inputs: baseInputs + [participantReference, representedEntityReference, issueReference],
            classification: classification,
            generation: generation,
            seed: seed,
            createdAt: createdAt
        )
        let positionReference = try reference(position)

        let commitment = try candidate.commitment.map { commitment in
            let recipient = try resolveRecipient(
                commitment.recipientLabel,
                resolved: resolved,
                participant: participantReference,
                organization: organizationReference
            )
            let content = try claim(
                commitment.content,
                taxonomy: .delegationClaim,
                support: support,
                evidence: evidenceReferences,
                confidence: candidate.confidence
            )
            let conditions = try commitment.conditions.map {
                try claim(
                    $0,
                    taxonomy: .delegationClaim,
                    support: support,
                    evidence: evidenceReferences,
                    confidence: candidate.confidence
                )
            }
            return try makeCommitment(
                resolved: resolved,
                representedEntity: representedEntityReference,
                recipient: recipient,
                issue: issueReference,
                content: content,
                conditions: conditions,
                deadline: commitment.deadlineDescription.map(CommitmentDeadline.described)
                    ?? .notStated,
                status: commitment.status,
                evidence: evidenceReferences,
                inputs: baseInputs + [representedEntityReference, recipient, issueReference, positionReference],
                classification: classification,
                generation: generation,
                seed: seed,
                createdAt: createdAt
            )
        }
        let commitmentReference = try commitment.map(reference)
        let decision = try candidate.decision.map { decision in
            try makeDecision(
                meetingID: resolved.meeting.meetingID,
                issue: issueReference,
                representedEntity: representedEntityReference,
                statement: try claim(
                    decision.content,
                    taxonomy: .meetingBuddyExtraction,
                    support: .uncertain,
                    evidence: evidenceReferences,
                    confidence: candidate.confidence
                ),
                evidence: evidenceReferences,
                inputs: baseInputs + [representedEntityReference, issueReference, positionReference],
                classification: classification,
                generation: generation,
                seed: seed,
                createdAt: createdAt
            )
        }
        let decisionReference = try decision.map(reference)
        let intervention = try makeIntervention(
            resolved: resolved,
            participant: participantReference,
            issue: issueReference,
            position: positionReference,
            commitment: commitmentReference,
            decision: decisionReference,
            interventionType: interventionType,
            summary: try claim(
                positionStatement,
                taxonomy: .meetingBuddyExtraction,
                support: support,
                evidence: evidenceReferences,
                confidence: candidate.confidence
            ),
            evidence: evidenceReferences,
            inputs: baseInputs + [
                participantReference,
                issueReference,
                positionReference
            ] + [commitmentReference, decisionReference].compactMap { $0 },
            classification: classification,
            generation: generation,
            seed: seed,
            createdAt: createdAt
        )
        return AnalysisUnitObjects(
            evidence: evidence,
            participant: participant,
            organization: organization,
            issue: issue,
            position: position,
            commitment: commitment,
            decision: decision,
            interventionCard: intervention
        )
    }

    public static func aggregateDelegationCards(
        units: [AnalysisUnitObjects],
        meeting: MeetingProfileV1,
        provider: ProviderMetadata,
        promptModules: [VersionedComponent] = DiplomaticAnalysisPrompt.modules,
        createdAt: UTCInstant
    ) throws -> [DelegationPositionCardV1] {
        let meetingReference = try reference(meeting)
        let groups = Dictionary(grouping: units) { unit in
            AggregationKey(
                representedEntity: unit.position.representedEntityRevision,
                issue: unit.position.issueRevision
            )
        }
        return try groups.keys.sorted().map { key in
            let members = groups[key]!.sorted {
                $0.position.revision.revisionID < $1.position.revision.revisionID
            }
            let positions = members.map(\.position)
            let positionReferences = try positions.map(reference)
            let capacityReferences = Array(Set(positions.map(\.speakingCapacityRevision))).sorted()
            let commitmentReferences = try members.compactMap(\.commitment).map(reference).sorted()
            let decisionReferences = try members.compactMap(\.decision).map(reference).sorted()
            let evidenceReferences = Array(Set(positions.flatMap { $0.revision.evidenceRevisions })).sorted()
            let reservations = positions.flatMap(\.reservations)
            let conditions = positions.flatMap(\.conditions)
            let classification = DataClassification.mostRestrictive(
                positions.map { $0.revision.dataClassification } + [meeting.revision.dataClassification]
            ) ?? .restricted
            let combinedStatement = positions.map { $0.statement.text }.joined(separator: " | ")
            guard combinedStatement.utf8.count <= 16_384 else {
                throw AIProviderContractError.invalidResponse("Delegation-position aggregation exceeded its bounded claim size.")
            }
            let zeroConfidence = try ConfidenceScore(millionths: 0)
            let lowestConfidence = positions.map(\.statement.confidence).min()
                ?? zeroConfidence
            let support: EvidenceSupportStatus = positions.contains {
                $0.statement.supportStatus == .uncertain
            } ? .uncertain : .supported
            let overall = try claim(
                combinedStatement,
                taxonomy: .meetingBuddyExtraction,
                support: support,
                evidence: evidenceReferences,
                confidence: lowestConfidence
            )
            let seed = "task006a-aggregation-v1:\(key.representedEntity.revisionID.canonicalString):\(key.issue.revisionID.canonicalString):\(positionReferences.map { $0.revisionID.canonicalString }.joined(separator: ","))"
            let generation = try GenerationMetadata(
                provider: provider,
                promptModuleVersions: promptModules + [
                    try VersionedComponent(identifier: "deterministic-aggregation", version: "1")
                ],
                outputSchemaVersion: .v1,
                templateVersion: "task006a-delegation-aggregation-v1",
                generatedAt: createdAt,
                privacyRoute: .localOnly
            )
            let inputs = [meetingReference, key.representedEntity, key.issue]
                + capacityReferences + positionReferences
                + commitmentReferences + decisionReferences
            let logicalID = DelegationPositionCardID(deterministicUUID(seed + ":logical"))
            let revisionID = RevisionID(deterministicUUID(seed + ":revision"))
            let draft = try DelegationPositionCardV1(
                revision: RevisionEnvelope(
                    logicalID: logicalID,
                    revisionID: revisionID,
                    schemaVersion: .v1,
                    lifecycleStatus: .draft,
                    validationState: .notValidated,
                    createdAt: createdAt,
                    createdBy: .provider,
                    inputRevisions: uniqueReferences(inputs),
                    sourceAssetRevisions: Array(Set(positions.flatMap { $0.revision.sourceAssetRevisions })).sorted(),
                    evidenceRevisions: evidenceReferences,
                    dataClassification: classification,
                    generationMetadata: generation
                ),
                meetingID: meeting.meetingID,
                representedEntityRevision: key.representedEntity,
                speakingCapacityRevisions: capacityReferences,
                issueRevision: key.issue,
                positionRevisions: positionReferences,
                commitmentRevisions: commitmentReferences,
                decisionRevisions: decisionReferences,
                overallPosition: overall,
                reservations: reservations,
                conditions: conditions,
                reviewStatus: .needsReview,
                userConfirmed: false
            )
            return try DelegationPositionCardV1(
                revision: publishedEnvelope(
                    draft.revision,
                    hash: try draft.calculatedSemanticContentHash(),
                    at: createdAt
                ),
                meetingID: draft.meetingID,
                representedEntityRevision: draft.representedEntityRevision,
                speakingCapacityRevisions: draft.speakingCapacityRevisions,
                issueRevision: draft.issueRevision,
                positionRevisions: draft.positionRevisions,
                commitmentRevisions: draft.commitmentRevisions,
                decisionRevisions: draft.decisionRevisions,
                overallPosition: draft.overallPosition,
                reservations: draft.reservations,
                conditions: draft.conditions,
                reviewStatus: draft.reviewStatus,
                userConfirmed: draft.userConfirmed
            )
        }
    }

    public static func reference<Object: SemanticRevisionContract>(
        _ value: Object
    ) throws -> SemanticRevisionReference {
        try SemanticRevisionReference(
            logicalID: value.revision.logicalID,
            revisionID: value.revision.revisionID
        )
    }

    private static func evidenceChunks(
        transcript: TranscriptSegmentV1,
        seed: String,
        classification: DataClassification,
        createdAt: UTCInstant
    ) throws -> [EvidenceRefV1] {
        let transcriptReference = try reference(transcript)
        var chunks: [(offset: UInt64, text: String)] = []
        var current = ""
        var currentBytes = 0
        var offset: UInt64 = 0
        var chunkOffset: UInt64 = 0
        for character in transcript.text {
            let text = String(character)
            let bytes = text.utf8.count
            if !current.isEmpty, currentBytes + bytes > 16_384 {
                chunks.append((chunkOffset, current))
                offset += UInt64(currentBytes)
                chunkOffset = offset
                current = ""
                currentBytes = 0
            }
            current.append(character)
            currentBytes += bytes
        }
        if !current.isEmpty { chunks.append((chunkOffset, current)) }
        guard !chunks.isEmpty else {
            throw AIProviderContractError.invalidRequest("Analysis evidence cannot be empty.")
        }
        return try chunks.enumerated().map { index, chunk in
            let logicalID = EvidenceID(deterministicUUID(seed + ":evidence:\(index):logical"))
            let revisionID = RevisionID(deterministicUUID(seed + ":evidence:\(index):revision"))
            let draft = try EvidenceRefV1(
                revision: RevisionEnvelope(
                    logicalID: logicalID,
                    revisionID: revisionID,
                    schemaVersion: .v1,
                    lifecycleStatus: .draft,
                    validationState: .notValidated,
                    createdAt: createdAt,
                    createdBy: .application,
                    inputRevisions: [transcriptReference],
                    sourceAssetRevisions: transcript.revision.sourceAssetRevisions,
                    dataClassification: classification
                ),
                location: .transcriptSegment(
                    source: transcriptReference,
                    textRange: try UTF8TextRange(
                        startOffset: chunk.offset,
                        length: UInt64(chunk.text.utf8.count)
                    )
                ),
                excerpt: EvidenceExcerpt(
                    text: chunk.text,
                    language: transcript.detectedLanguage,
                    translationStatus: .sourceOnly
                ),
                confidence: transcript.confidence
            )
            return try EvidenceRefV1(
                revision: publishedEnvelope(
                    draft.revision,
                    hash: try draft.calculatedSemanticContentHash(),
                    at: createdAt
                ),
                location: draft.location,
                excerpt: draft.excerpt,
                confidence: draft.confidence
            )
        }
    }

    private static func makeOrganizationIfNeeded(
        actor: ActorV1,
        evidence: [SemanticRevisionReference],
        inputs: [SemanticRevisionReference],
        classification: DataClassification,
        generation: GenerationMetadata,
        seed: String,
        confidence: ConfidenceScore,
        createdAt: UTCInstant
    ) throws -> OrganizationV1? {
        let kind: OrganizationKind
        switch actor.identity {
        case .country: kind = .country
        case .internationalOrganization: kind = .internationalOrganization
        case .formalGroup: kind = .formalGroup
        case .unOrgan: kind = .unOrgan
        case .unSecretariat: kind = .unSecretariat
        case .other: kind = .other
        case .person, .unidentifiedParticipant:
            return nil
        }
        let actorReference = try reference(actor)
        let logicalID = OrganizationID(deterministicUUID(seed + ":organization:logical"))
        let revisionID = RevisionID(deterministicUUID(seed + ":organization:revision"))
        let draft = try OrganizationV1(
            revision: RevisionEnvelope(
                logicalID: logicalID,
                revisionID: revisionID,
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: createdAt,
                createdBy: .provider,
                inputRevisions: uniqueReferences(inputs + [actorReference]),
                evidenceRevisions: evidence,
                dataClassification: classification,
                generationMetadata: generation
            ),
            actorRevision: actorReference,
            kind: kind,
            displayName: actor.displayName,
            countryCode: actor.identity.countryCode,
            confidence: confidence,
            reviewStatus: .needsReview,
            userConfirmed: false
        )
        return try OrganizationV1(
            revision: publishedEnvelope(
                draft.revision,
                hash: try draft.calculatedSemanticContentHash(),
                at: createdAt
            ),
            actorRevision: draft.actorRevision,
            kind: draft.kind,
            displayName: draft.displayName,
            countryCode: draft.countryCode,
            confidence: draft.confidence,
            reviewStatus: draft.reviewStatus,
            userConfirmed: draft.userConfirmed
        )
    }

    private static func makeParticipant(
        actor: ActorV1,
        capacity: SpeakingCapacityV1,
        meetingID: MeetingID,
        organizationReference: SemanticRevisionReference?,
        evidence: [SemanticRevisionReference],
        inputs: [SemanticRevisionReference],
        classification: DataClassification,
        generation: GenerationMetadata,
        seed: String,
        confidence: ConfidenceScore,
        createdAt: UTCInstant
    ) throws -> ParticipantV1 {
        let actorReference = try reference(actor)
        let capacityReference = try reference(capacity)
        let logicalID = ParticipantID(deterministicUUID(seed + ":participant:logical"))
        let revisionID = RevisionID(deterministicUUID(seed + ":participant:revision"))
        let organizationReferences = [organizationReference].compactMap { $0 }
        let kind: ParticipantKind = switch capacity.meetingRole {
        case .chair: .chair
        case .expert: .expert
        case .observer: .observer
        case .briefer: .briefer
        case .unidentified: .unidentified
        case .delegate, .secretariatOfficial, .groupRepresentative, .other: .other
        case .unrecognized: .other
        }
        let draft = try ParticipantV1(
            revision: RevisionEnvelope(
                logicalID: logicalID,
                revisionID: revisionID,
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: createdAt,
                createdBy: .provider,
                inputRevisions: uniqueReferences(
                    inputs + [actorReference, capacityReference] + organizationReferences
                ),
                evidenceRevisions: evidence,
                dataClassification: classification,
                generationMetadata: generation
            ),
            meetingID: meetingID,
            actorRevision: actorReference,
            speakingCapacityRevisions: [capacityReference],
            organizationRevisions: organizationReferences,
            kind: kind,
            displayName: actor.displayName,
            confidence: confidence,
            reviewStatus: .needsReview,
            userConfirmed: false
        )
        return try ParticipantV1(
            revision: publishedEnvelope(
                draft.revision,
                hash: try draft.calculatedSemanticContentHash(),
                at: createdAt
            ),
            meetingID: draft.meetingID,
            actorRevision: draft.actorRevision,
            speakingCapacityRevisions: draft.speakingCapacityRevisions,
            organizationRevisions: draft.organizationRevisions,
            kind: draft.kind,
            displayName: draft.displayName,
            confidence: draft.confidence,
            reviewStatus: draft.reviewStatus,
            userConfirmed: draft.userConfirmed
        )
    }

    private static func makeIssue(
        meetingID: MeetingID,
        title: EvidenceLinkedClaim,
        evidence: [SemanticRevisionReference],
        inputs: [SemanticRevisionReference],
        classification: DataClassification,
        generation: GenerationMetadata,
        seed: String,
        createdAt: UTCInstant
    ) throws -> IssueV1 {
        let logicalID = IssueID(deterministicUUID(seed + ":issue:logical"))
        let revisionID = RevisionID(deterministicUUID(seed + ":issue:revision"))
        let draft = try IssueV1(
            revision: RevisionEnvelope(
                logicalID: logicalID,
                revisionID: revisionID,
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: createdAt,
                createdBy: .provider,
                inputRevisions: uniqueReferences(inputs),
                evidenceRevisions: evidence,
                dataClassification: classification,
                generationMetadata: generation
            ),
            meetingID: meetingID,
            title: title,
            reviewStatus: .needsReview,
            userConfirmed: false
        )
        return try IssueV1(
            revision: publishedEnvelope(draft.revision, hash: try draft.calculatedSemanticContentHash(), at: createdAt),
            meetingID: draft.meetingID,
            title: draft.title,
            summary: draft.summary,
            reviewStatus: draft.reviewStatus,
            userConfirmed: draft.userConfirmed
        )
    }

    private static func makePosition(
        resolved: AnalysisResolvedUnit,
        representedEntity: SemanticRevisionReference,
        issue: SemanticRevisionReference,
        positionType: PositionType,
        statement: EvidenceLinkedClaim,
        reservations: [EvidenceLinkedClaim],
        conditions: [EvidenceLinkedClaim],
        evidence: [SemanticRevisionReference],
        inputs: [SemanticRevisionReference],
        classification: DataClassification,
        generation: GenerationMetadata,
        seed: String,
        createdAt: UTCInstant
    ) throws -> PositionV1 {
        let logicalID = PositionID(deterministicUUID(seed + ":position:logical"))
        let revisionID = RevisionID(deterministicUUID(seed + ":position:revision"))
        let draft = try PositionV1(
            revision: RevisionEnvelope(
                logicalID: logicalID,
                revisionID: revisionID,
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: createdAt,
                createdBy: .provider,
                inputRevisions: uniqueReferences(inputs),
                sourceAssetRevisions: resolved.transcript.revision.sourceAssetRevisions,
                evidenceRevisions: evidence,
                dataClassification: classification,
                generationMetadata: generation
            ),
            meetingID: resolved.meeting.meetingID,
            actorRevision: try reference(resolved.speakerActor),
            representedEntityRevision: representedEntity,
            speakingCapacityRevision: try reference(resolved.speakingCapacity),
            issueRevision: issue,
            positionType: positionType,
            statement: statement,
            reservations: reservations,
            conditions: conditions,
            effectiveTimeRange: resolved.transcript.timeRange,
            comparisonState: .unknown,
            reviewStatus: .needsReview,
            userConfirmed: false
        )
        return try PositionV1(
            revision: publishedEnvelope(draft.revision, hash: try draft.calculatedSemanticContentHash(), at: createdAt),
            meetingID: draft.meetingID,
            actorRevision: draft.actorRevision,
            representedEntityRevision: draft.representedEntityRevision,
            speakingCapacityRevision: draft.speakingCapacityRevision,
            issueRevision: draft.issueRevision,
            positionType: draft.positionType,
            statement: draft.statement,
            reservations: draft.reservations,
            conditions: draft.conditions,
            effectiveTimeRange: draft.effectiveTimeRange,
            comparisonState: draft.comparisonState,
            reviewStatus: draft.reviewStatus,
            userConfirmed: draft.userConfirmed
        )
    }

    private static func makeCommitment(
        resolved: AnalysisResolvedUnit,
        representedEntity: SemanticRevisionReference,
        recipient: SemanticRevisionReference,
        issue: SemanticRevisionReference,
        content: EvidenceLinkedClaim,
        conditions: [EvidenceLinkedClaim],
        deadline: CommitmentDeadline,
        status: CommitmentStatus,
        evidence: [SemanticRevisionReference],
        inputs: [SemanticRevisionReference],
        classification: DataClassification,
        generation: GenerationMetadata,
        seed: String,
        createdAt: UTCInstant
    ) throws -> CommitmentV1 {
        let logicalID = CommitmentID(deterministicUUID(seed + ":commitment:logical"))
        let revisionID = RevisionID(deterministicUUID(seed + ":commitment:revision"))
        let draft = try CommitmentV1(
            revision: RevisionEnvelope(
                logicalID: logicalID,
                revisionID: revisionID,
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: createdAt,
                createdBy: .provider,
                inputRevisions: uniqueReferences(inputs),
                sourceAssetRevisions: resolved.transcript.revision.sourceAssetRevisions,
                evidenceRevisions: evidence,
                dataClassification: classification,
                generationMetadata: generation
            ),
            meetingID: resolved.meeting.meetingID,
            actorRevision: try reference(resolved.speakerActor),
            representedEntityRevision: representedEntity,
            speakingCapacityRevision: try reference(resolved.speakingCapacity),
            recipientRevision: recipient,
            issueRevision: issue,
            content: content,
            conditions: conditions,
            deadline: deadline,
            status: status,
            reviewStatus: .needsReview,
            userConfirmed: false
        )
        return try CommitmentV1(
            revision: publishedEnvelope(draft.revision, hash: try draft.calculatedSemanticContentHash(), at: createdAt),
            meetingID: draft.meetingID,
            actorRevision: draft.actorRevision,
            representedEntityRevision: draft.representedEntityRevision,
            speakingCapacityRevision: draft.speakingCapacityRevision,
            recipientRevision: draft.recipientRevision,
            issueRevision: draft.issueRevision,
            content: draft.content,
            conditions: draft.conditions,
            deadline: draft.deadline,
            status: draft.status,
            reviewStatus: draft.reviewStatus,
            userConfirmed: draft.userConfirmed
        )
    }

    private static func makeDecision(
        meetingID: MeetingID,
        issue: SemanticRevisionReference,
        representedEntity: SemanticRevisionReference,
        statement: EvidenceLinkedClaim,
        evidence: [SemanticRevisionReference],
        inputs: [SemanticRevisionReference],
        classification: DataClassification,
        generation: GenerationMetadata,
        seed: String,
        createdAt: UTCInstant
    ) throws -> DecisionV1 {
        let logicalID = DecisionID(deterministicUUID(seed + ":decision:logical"))
        let revisionID = RevisionID(deterministicUUID(seed + ":decision:revision"))
        let draft = try DecisionV1(
            revision: RevisionEnvelope(
                logicalID: logicalID,
                revisionID: revisionID,
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: createdAt,
                createdBy: .provider,
                inputRevisions: uniqueReferences(inputs),
                evidenceRevisions: evidence,
                dataClassification: classification,
                generationMetadata: generation
            ),
            meetingID: meetingID,
            issueRevision: issue,
            decisionType: .uncertain,
            statement: statement,
            responsibleEntityRevisions: [representedEntity],
            reviewStatus: .needsReview,
            userConfirmed: false
        )
        return try DecisionV1(
            revision: publishedEnvelope(draft.revision, hash: try draft.calculatedSemanticContentHash(), at: createdAt),
            meetingID: draft.meetingID,
            issueRevision: draft.issueRevision,
            decisionType: draft.decisionType,
            statement: draft.statement,
            responsibleEntityRevisions: draft.responsibleEntityRevisions,
            effectiveTimeRange: draft.effectiveTimeRange,
            reviewStatus: draft.reviewStatus,
            userConfirmed: draft.userConfirmed
        )
    }

    private static func makeIntervention(
        resolved: AnalysisResolvedUnit,
        participant: SemanticRevisionReference,
        issue: SemanticRevisionReference,
        position: SemanticRevisionReference,
        commitment: SemanticRevisionReference?,
        decision: SemanticRevisionReference?,
        interventionType: InterventionType,
        summary: EvidenceLinkedClaim,
        evidence: [SemanticRevisionReference],
        inputs: [SemanticRevisionReference],
        classification: DataClassification,
        generation: GenerationMetadata,
        seed: String,
        createdAt: UTCInstant
    ) throws -> InterventionCardV1 {
        let logicalID = InterventionCardID(deterministicUUID(seed + ":intervention:logical"))
        let revisionID = RevisionID(deterministicUUID(seed + ":intervention:revision"))
        let draft = try InterventionCardV1(
            revision: RevisionEnvelope(
                logicalID: logicalID,
                revisionID: revisionID,
                schemaVersion: .v1,
                lifecycleStatus: .draft,
                validationState: .notValidated,
                createdAt: createdAt,
                createdBy: .provider,
                inputRevisions: uniqueReferences(inputs),
                sourceAssetRevisions: resolved.transcript.revision.sourceAssetRevisions,
                evidenceRevisions: evidence,
                dataClassification: classification,
                generationMetadata: generation
            ),
            meetingID: resolved.meeting.meetingID,
            speakerAssignmentRevision: try reference(resolved.speakerAssignment),
            participantRevision: participant,
            timeRange: resolved.transcript.timeRange,
            interventionType: interventionType,
            shortSummary: summary,
            issueRevisions: [issue],
            positionRevisions: [position],
            commitmentRevisions: [commitment].compactMap { $0 },
            decisionRevisions: [decision].compactMap { $0 },
            reviewStatus: .needsReview,
            userConfirmed: false
        )
        return try InterventionCardV1(
            revision: publishedEnvelope(draft.revision, hash: try draft.calculatedSemanticContentHash(), at: createdAt),
            meetingID: draft.meetingID,
            speakerAssignmentRevision: draft.speakerAssignmentRevision,
            participantRevision: draft.participantRevision,
            timeRange: draft.timeRange,
            interventionType: draft.interventionType,
            shortSummary: draft.shortSummary,
            issueRevisions: draft.issueRevisions,
            positionRevisions: draft.positionRevisions,
            commitmentRevisions: draft.commitmentRevisions,
            decisionRevisions: draft.decisionRevisions,
            notableWording: draft.notableWording,
            reviewStatus: draft.reviewStatus,
            userConfirmed: draft.userConfirmed
        )
    }

    private static func resolveRecipient(
        _ label: String?,
        resolved: AnalysisResolvedUnit,
        participant: SemanticRevisionReference,
        organization: SemanticRevisionReference?
    ) throws -> SemanticRevisionReference {
        guard let label else {
            return organization ?? participant
        }
        let matches = ([resolved.speakerActor, resolved.representedActor]
            + resolved.knownRecipientActors).filter { $0.displayName == label }
        let unique = Dictionary(grouping: matches, by: { $0.actorID.canonicalString }).values
            .compactMap(\.first)
        guard unique.count == 1, let actor = unique.first else {
            throw AIProviderContractError.invalidResponse(
                "A commitment recipient label did not resolve to exactly one existing Actor."
            )
        }
        if actor.actorID == resolved.representedActor.actorID {
            return organization ?? participant
        }
        if actor.actorID == resolved.speakerActor.actorID { return participant }
        return try reference(actor)
    }

    private static func claim(
        _ text: String,
        taxonomy: ClaimTaxonomy,
        support: EvidenceSupportStatus,
        evidence: [SemanticRevisionReference],
        confidence: ConfidenceScore
    ) throws -> EvidenceLinkedClaim {
        try EvidenceLinkedClaim(
            text: text,
            taxonomy: taxonomy,
            supportStatus: support,
            evidenceRevisions: evidence,
            confidence: confidence
        )
    }

    private static func digest<T: Encodable>(_ value: T) throws -> ContentDigest {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let digest = SHA256.hash(data: try encoder.encode(value))
        return try ContentDigest(
            algorithm: .sha256,
            lowercaseHex: digest.map { String(format: "%02x", $0) }.joined()
        )
    }

    private static func uniqueReferences(
        _ values: [SemanticRevisionReference]
    ) -> [SemanticRevisionReference] {
        Array(Set(values)).sorted()
    }

    private static func deterministicUUID(_ seed: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func publishedEnvelope<Tag: LogicalObjectIDScope>(
        _ draft: RevisionEnvelope<Tag>,
        hash: ContentDigest,
        at createdAt: UTCInstant
    ) throws -> RevisionEnvelope<Tag> {
        try RevisionEnvelope(
            logicalID: draft.logicalID,
            revisionID: draft.revisionID,
            schemaVersion: draft.schemaVersion,
            lifecycleStatus: .published,
            validationState: .valid,
            createdAt: draft.createdAt,
            createdBy: draft.createdBy,
            publishedAt: createdAt,
            supersedesRevisionID: draft.supersedesRevisionID,
            inputRevisions: draft.inputRevisions,
            sourceAssetRevisions: draft.sourceAssetRevisions,
            evidenceRevisions: draft.evidenceRevisions,
            dataClassification: draft.dataClassification,
            generationMetadata: draft.generationMetadata,
            semanticContentHash: hash
        )
    }

    private struct AggregationKey: Hashable, Comparable {
        let representedEntity: SemanticRevisionReference
        let issue: SemanticRevisionReference

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.representedEntity != rhs.representedEntity {
                return lhs.representedEntity < rhs.representedEntity
            }
            return lhs.issue < rhs.issue
        }
    }
}

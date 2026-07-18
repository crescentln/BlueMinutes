/// A validated, type-erased view used only to check exact dependency classification.
public struct ResolvedDependencyClassification: Hashable, Sendable, DomainValidatable {
    public let revisionReference: SemanticRevisionReference
    public let dataClassification: DataClassification

    public init<Object: SemanticRevisionContract>(resolving object: Object) throws {
        try object.validate()
        revisionReference = try SemanticRevisionReference(
            logicalID: object.revision.logicalID,
            revisionID: object.revision.revisionID
        )
        dataClassification = object.revision.dataClassification
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = revisionReference.validationIssues()
        if !dataClassification.isKnown {
            issues.append(
                ValidationIssue(
                    code: .unsupportedValue,
                    path: "resolved_dependency.data_classification",
                    message: "A resolved dependency must use a supported data classification."
                )
            )
        }
        return issues
    }
}

/// Pure cross-object checks that require resolved Task 003A/003B values.
public enum InputContractGraphValidation {
    public static func validate(
        meeting: MeetingProfileV1,
        sourceAssets: [SourceAssetV1],
        actors: [ActorV1],
        additionalDependencies: [ResolvedDependencyClassification] = []
    ) throws {
        try meeting.validate()
        for source in sourceAssets { try source.validate() }
        for actor in actors { try actor.validate() }

        let sourceReferences = try sourceAssets.map(reference)
        let actorReferences = try actors.map(reference)
        var issues = duplicateIssues(in: sourceReferences, path: "source_assets")
        issues.append(contentsOf: duplicateIssues(in: actorReferences, path: "actors"))

        for requiredSource in meeting.revision.sourceAssetRevisions {
            guard let sourceIndex = sourceReferences.firstIndex(of: requiredSource) else {
                issues.append(issue(.missingRequiredValue, "source_assets", "A MeetingProfile source revision was not resolved."))
                continue
            }
            if sourceAssets[sourceIndex].meetingID != meeting.meetingID {
                issues.append(issue(.inconsistentValue, "source_assets.meeting_id", "Every meeting source must belong to the same meeting."))
            }
        }
        if let organization = meeting.organizationOrUNBody?.actorRevision,
           !actorReferences.contains(organization)
        {
            issues.append(issue(.missingRequiredValue, "actors", "The resolved meeting organization Actor was not provided."))
        }
        for priorityActorID in meeting.priorityActorIDs
            where !actors.contains(where: { $0.actorID == priorityActorID })
        {
            issues.append(issue(.missingRequiredValue, "actors", "A priority Actor logical ID was not resolved."))
        }
        let resolvedDependencies = try sourceAssets.map {
            try ResolvedDependencyClassification(resolving: $0)
        } + actors.map {
            try ResolvedDependencyClassification(resolving: $0)
        } + additionalDependencies
        issues.append(contentsOf: dependencyClassificationIssues(
            revision: meeting.revision,
            resolvedDependencies: resolvedDependencies,
            path: "meeting.revision.data_classification"
        ))
        try throwIfNeeded(issues)
    }

    public static func validate(
        transcript: TranscriptSegmentV1,
        sourceAsset: SourceAssetV1,
        additionalDependencies: [ResolvedDependencyClassification] = []
    ) throws {
        try transcript.validate()
        try sourceAsset.validate()
        let sourceReference = try reference(sourceAsset)
        var issues: [ValidationIssue] = []
        if transcript.sourceAssetRevision != sourceReference {
            issues.append(issue(.inconsistentValue, "transcript.source_provenance", "The resolved SourceAsset does not match transcript provenance."))
        }
        if transcript.meetingID != sourceAsset.meetingID {
            issues.append(issue(.inconsistentValue, "transcript.meeting_id", "Transcript and source asset must belong to the same meeting."))
        }
        if sourceAsset.assetType != .audio, sourceAsset.assetType != .video {
            issues.append(issue(.inconsistentValue, "source_asset.asset_type", "A transcript source must be an audio or video asset."))
        }
        if let media = sourceAsset.media {
            if UInt64(transcript.timeRange.endMilliseconds) > media.durationMilliseconds {
                issues.append(issue(.invalidRange, "transcript.time_range", "The transcript range exceeds source media duration."))
            }
            if transcript.speechSourceKind != media.speechSourceKind {
                issues.append(issue(.inconsistentValue, "transcript.source_provenance", "Transcript provenance must match the source track's speech-source kind."))
            }
        }
        let resolvedDependencies = [
            try ResolvedDependencyClassification(resolving: sourceAsset)
        ] + additionalDependencies
        issues.append(contentsOf: dependencyClassificationIssues(
            revision: transcript.revision,
            resolvedDependencies: resolvedDependencies,
            path: "transcript.revision.data_classification"
        ))
        try throwIfNeeded(issues)
    }

    public static func validate(
        translation: TranslationSegmentV1,
        sourceTranscript: TranscriptSegmentV1,
        additionalDependencies: [ResolvedDependencyClassification] = []
    ) throws {
        try translation.validate()
        try sourceTranscript.validate()
        var issues: [ValidationIssue] = []
        if translation.sourceSegmentRevision != (try reference(sourceTranscript)) {
            issues.append(issue(.inconsistentValue, "translation.source_segment_revision", "The resolved TranscriptSegment does not match the translation source."))
        }
        if translation.meetingID != sourceTranscript.meetingID {
            issues.append(issue(.inconsistentValue, "translation.meeting_id", "Translation and source transcript must belong to the same meeting."))
        }
        if translation.sourceLanguage != sourceTranscript.detectedLanguage {
            issues.append(issue(.inconsistentValue, "translation.source_language", "Translation source language must match the transcript language."))
        }
        if translation.sourceTextHash != (try TranslationSegmentV1.calculateSourceTextHash(sourceTranscript.text)) {
            issues.append(issue(.inconsistentValue, "translation.source_text_hash", "The source-text hash does not match the exact transcript UTF-8 bytes."))
        }
        let resolvedDependencies = [
            try ResolvedDependencyClassification(resolving: sourceTranscript)
        ] + additionalDependencies
        issues.append(contentsOf: dependencyClassificationIssues(
            revision: translation.revision,
            resolvedDependencies: resolvedDependencies,
            path: "translation.revision.data_classification"
        ))
        try throwIfNeeded(issues)
    }

    public static func validate(
        actor: ActorV1,
        affiliations: [ActorV1],
        additionalDependencies: [ResolvedDependencyClassification] = []
    ) throws {
        try actor.validate()
        for affiliation in affiliations { try affiliation.validate() }
        let affiliationReferences = try affiliations.map(reference)
        var issues = duplicateIssues(in: affiliationReferences, path: "affiliations")
        if let affiliationRevision = actor.affiliationRevision,
           !affiliationReferences.contains(affiliationRevision)
        {
            issues.append(issue(.missingRequiredValue, "affiliations", "The exact affiliated Actor revision was not resolved."))
        }
        let resolvedDependencies = try affiliations.map {
            try ResolvedDependencyClassification(resolving: $0)
        } + additionalDependencies
        issues.append(contentsOf: dependencyClassificationIssues(
            revision: actor.revision,
            resolvedDependencies: resolvedDependencies,
            path: "actor.revision.data_classification"
        ))
        try throwIfNeeded(issues)
    }

    public static func validate(
        capacity: SpeakingCapacityV1,
        actors: [ActorV1],
        additionalDependencies: [ResolvedDependencyClassification] = []
    ) throws {
        try capacity.validate()
        for actor in actors { try actor.validate() }
        let actorReferences = try actors.map(reference)
        var issues = duplicateIssues(in: actorReferences, path: "actors")
        if !actorReferences.contains(capacity.speakerActorRevision) {
            issues.append(issue(.missingRequiredValue, "actors", "The speaking-capacity speaker Actor was not resolved."))
        }
        for relationship in capacity.representationRelationships
            where !actorReferences.contains(relationship.entityRevision)
        {
            issues.append(issue(.missingRequiredValue, "actors", "A represented entity Actor was not resolved."))
        }
        if capacity.meetingRole == .unidentified,
           let speakerIndex = actorReferences.firstIndex(of: capacity.speakerActorRevision),
           case .unidentifiedParticipant = actors[speakerIndex].identity
        {
            // Valid explicit unknown identity and capacity.
        } else if capacity.meetingRole == .unidentified {
            issues.append(issue(.inconsistentValue, "capacity.meeting_role", "An unidentified capacity requires an unidentified-participant Actor."))
        }
        let resolvedDependencies = try actors.map {
            try ResolvedDependencyClassification(resolving: $0)
        } + additionalDependencies
        issues.append(contentsOf: dependencyClassificationIssues(
            revision: capacity.revision,
            resolvedDependencies: resolvedDependencies,
            path: "capacity.revision.data_classification"
        ))
        try throwIfNeeded(issues)
    }

    public static func validate(
        assignment: SpeakerAssignmentV1,
        transcripts: [TranscriptSegmentV1],
        actor: ActorV1,
        capacity: SpeakingCapacityV1,
        evidence: [EvidenceRefV1],
        additionalDependencies: [ResolvedDependencyClassification] = []
    ) throws {
        try assignment.validate()
        for transcript in transcripts { try transcript.validate() }
        try actor.validate()
        try capacity.validate()
        for reference in evidence { try reference.validate() }

        let transcriptReferences = try transcripts.map(reference)
        let evidenceReferences = try evidence.map(reference)
        var issues = duplicateIssues(in: transcriptReferences, path: "transcripts")
        issues.append(contentsOf: duplicateIssues(in: evidenceReferences, path: "evidence"))
        if assignment.transcriptSegmentRevisions != transcriptReferences.sorted() {
            issues.append(issue(.inconsistentValue, "assignment.transcript_segment_revisions", "Resolved transcripts must match the assignment's exact segment set."))
        }
        let actorReference = try reference(actor)
        if assignment.actorRevision != actorReference {
            issues.append(issue(.inconsistentValue, "assignment.actor_revision", "The resolved Actor does not match the assignment."))
        }
        let capacityReference = try reference(capacity)
        if assignment.speakingCapacityRevision != capacityReference {
            issues.append(issue(.inconsistentValue, "assignment.speaking_capacity_revision", "The resolved SpeakingCapacity does not match the assignment."))
        }
        if capacity.speakerActorRevision != actorReference {
            issues.append(issue(.inconsistentValue, "capacity.speaker_actor_revision", "The capacity speaker and assigned Actor must match."))
        }
        if capacity.meetingID != assignment.meetingID
            || transcripts.contains(where: { $0.meetingID != assignment.meetingID })
        {
            issues.append(issue(.inconsistentValue, "assignment.meeting_id", "Assignment, capacity, and transcript segments must belong to the same meeting."))
        }
        if assignment.evidenceRevisions != evidenceReferences.sorted() {
            issues.append(issue(.inconsistentValue, "assignment.revision.evidence_revisions", "Resolved evidence must match the assignment's exact evidence set."))
        }
        let resolvedDependencies = try transcripts.map {
            try ResolvedDependencyClassification(resolving: $0)
        } + [
            try ResolvedDependencyClassification(resolving: actor),
            try ResolvedDependencyClassification(resolving: capacity)
        ] + evidence.map {
            try ResolvedDependencyClassification(resolving: $0)
        } + additionalDependencies
        issues.append(contentsOf: dependencyClassificationIssues(
            revision: assignment.revision,
            resolvedDependencies: resolvedDependencies,
            path: "assignment.revision.data_classification"
        ))
        try throwIfNeeded(issues)
    }

    private static func reference<Object: SemanticRevisionContract>(
        _ object: Object
    ) throws -> SemanticRevisionReference {
        try SemanticRevisionReference(
            logicalID: object.revision.logicalID,
            revisionID: object.revision.revisionID
        )
    }

    private static func dependencyClassificationIssues<Tag: LogicalObjectIDScope>(
        revision: RevisionEnvelope<Tag>,
        resolvedDependencies: [ResolvedDependencyClassification],
        path: String
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        for dependency in resolvedDependencies {
            issues.append(contentsOf: dependency.validationIssues())
        }
        issues.append(
            contentsOf: duplicateIssues(
                in: resolvedDependencies.map(\.revisionReference),
                path: "resolved_dependencies.revision_reference"
            )
        )

        let requiredReferences = Array(
            Set(
                revision.inputRevisions
                    + revision.sourceAssetRevisions
                    + revision.evidenceRevisions
            )
        ).sorted()
        var classifications: [DataClassification] = []
        for requiredReference in requiredReferences {
            let matches = resolvedDependencies.filter {
                $0.revisionReference == requiredReference
            }
            if matches.isEmpty {
                issues.append(
                    issue(
                        .missingRequiredValue,
                        "resolved_dependencies",
                        "Every exact envelope dependency must be resolved for classification inheritance."
                    )
                )
            } else if matches.count == 1, let match = matches.first {
                classifications.append(match.dataClassification)
            }
        }
        if let required = DataClassification.mostRestrictive(classifications),
           revision.dataClassification.restrictionRank < required.restrictionRank
        {
            issues.append(
                issue(
                    .inconsistentValue,
                    path,
                    "A derived contract cannot be less restrictive than any exact envelope dependency."
                )
            )
        }
        return issues
    }

    private static func issue(
        _ code: ValidationIssueCode,
        _ path: String,
        _ message: String
    ) -> ValidationIssue {
        ValidationIssue(code: code, path: path, message: message)
    }

    private static func throwIfNeeded(_ issues: [ValidationIssue]) throws {
        guard issues.isEmpty else { throw DomainValidationError(issues: issues) }
    }
}

/// Pure cross-object checks for Task 006A identity, capacity, evidence aggregation,
/// and most-restrictive-classification inheritance.
public enum IntelligenceGraphValidation {
    public static func validate(
        participants: [ParticipantV1],
        organizations: [OrganizationV1],
        issues: [IssueV1],
        positions: [PositionV1],
        commitments: [CommitmentV1],
        decisions: [DecisionV1],
        interventionCards: [InterventionCardV1],
        delegationPositionCards: [DelegationPositionCardV1],
        actors: [ActorV1],
        capacities: [SpeakingCapacityV1],
        assignments: [SpeakerAssignmentV1],
        additionalDependencies: [ResolvedDependencyClassification]
    ) throws {
        try validateAll(participants)
        try validateAll(organizations)
        try validateAll(issues)
        try validateAll(positions)
        try validateAll(commitments)
        try validateAll(decisions)
        try validateAll(interventionCards)
        try validateAll(delegationPositionCards)
        try validateAll(actors)
        try validateAll(capacities)
        try validateAll(assignments)

        let actorByReference = try dictionary(actors)
        let capacityByReference = try dictionary(capacities)
        let assignmentByReference = try dictionary(assignments)
        let participantByReference = try dictionary(participants)
        let organizationByReference = try dictionary(organizations)
        let issueByReference = try dictionary(issues)
        let positionByReference = try dictionary(positions)
        let commitmentByReference = try dictionary(commitments)
        let decisionByReference = try dictionary(decisions)

        var issuesFound: [ValidationIssue] = []
        for organization in organizations {
            guard let actor = actorByReference[organization.actorRevision] else {
                issuesFound.append(issue(.missingRequiredValue, "organization.actor_revision", "The organization Actor was not resolved."))
                continue
            }
            if !organizationKindMatchesIdentity(organization, actor: actor) {
                issuesFound.append(issue(.inconsistentValue, "organization.kind", "Organization kind, country code, and Actor identity must agree."))
            }
        }

        for participant in participants {
            guard let actor = actorByReference[participant.actorRevision] else {
                issuesFound.append(issue(.missingRequiredValue, "participant.actor_revision", "The participant Actor was not resolved."))
                continue
            }
            if !participantKindMatchesIdentity(participant.kind, actor.identity) {
                issuesFound.append(issue(.inconsistentValue, "participant.kind", "Participant kind is incompatible with the Actor identity."))
            }
            let resolvedCapacities = participant.speakingCapacityRevisions.compactMap {
                capacityByReference[$0]
            }
            if resolvedCapacities.count != participant.speakingCapacityRevisions.count {
                issuesFound.append(issue(.missingRequiredValue, "participant.speaking_capacity_revisions", "Every participant capacity must be resolved."))
            }
            if resolvedCapacities.contains(where: {
                $0.speakerActorRevision != participant.actorRevision
                    || $0.meetingID != participant.meetingID
            }) {
                issuesFound.append(issue(.inconsistentValue, "participant.speaking_capacity_revisions", "Participant capacities must belong to the same meeting and speaker Actor."))
            }
            for organizationReference in participant.organizationRevisions {
                guard let organization = organizationByReference[organizationReference] else {
                    issuesFound.append(issue(.missingRequiredValue, "participant.organization_revisions", "A participant organization was not resolved."))
                    continue
                }
                let represented = resolvedCapacities.contains { capacity in
                    capacity.representationRelationships.contains {
                        $0.entityRevision == organization.actorRevision
                    }
                }
                if !represented {
                    issuesFound.append(issue(.inconsistentValue, "participant.organization_revisions", "A participant organization must be grounded in an exact capacity relationship."))
                }
            }
            _ = actor
        }

        for position in positions {
            guard let capacity = capacityByReference[position.speakingCapacityRevision],
                  actorByReference[position.actorRevision] != nil,
                  issueByReference[position.issueRevision] != nil
            else {
                issuesFound.append(issue(.missingRequiredValue, "position", "Position actor, capacity, or issue was not resolved."))
                continue
            }
            if capacity.meetingID != position.meetingID
                || capacity.speakerActorRevision != position.actorRevision
            {
                issuesFound.append(issue(.inconsistentValue, "position.speaking_capacity_revision", "Position actor and meeting must match the exact speaking capacity."))
            }
            let representedActor: SemanticRevisionReference?
            if let participant = participantByReference[position.representedEntityRevision] {
                representedActor = participant.actorRevision
            } else if let organization = organizationByReference[position.representedEntityRevision] {
                representedActor = organization.actorRevision
            } else {
                representedActor = nil
                issuesFound.append(issue(.missingRequiredValue, "position.represented_entity_revision", "The represented participant or organization was not resolved."))
            }
            if let representedActor,
               representedActor != position.actorRevision,
               !capacity.representationRelationships.contains(where: {
                   $0.entityRevision == representedActor
               })
            {
                issuesFound.append(issue(.inconsistentValue, "position.represented_entity_revision", "A group or organization position must be grounded in the speaker's exact representation relationship."))
            }
        }

        for commitment in commitments {
            if positionByReference.values.contains(where: {
                $0.issueRevision == commitment.issueRevision
                    && $0.actorRevision == commitment.actorRevision
                    && $0.speakingCapacityRevision == commitment.speakingCapacityRevision
            }) == false {
                issuesFound.append(issue(.inconsistentValue, "commitment", "A commitment must remain tied to the same actor, capacity, and issue context as a resolved position."))
            }
        }

        for card in interventionCards {
            guard assignmentByReference[card.speakerAssignmentRevision] != nil,
                  participantByReference[card.participantRevision] != nil,
                  card.issueRevisions.allSatisfy({ issueByReference[$0] != nil }),
                  card.positionRevisions.allSatisfy({ positionByReference[$0] != nil }),
                  card.commitmentRevisions.allSatisfy({ commitmentByReference[$0] != nil }),
                  card.decisionRevisions.allSatisfy({ decisionByReference[$0] != nil })
            else {
                issuesFound.append(issue(.missingRequiredValue, "intervention_card", "Every intervention-card identity and semantic output must resolve exactly."))
                continue
            }
        }

        for card in delegationPositionCards {
            guard issueByReference[card.issueRevision] != nil else {
                issuesFound.append(issue(.missingRequiredValue, "delegation_position_card.issue_revision", "The delegation-card issue was not resolved."))
                continue
            }
            let cardPositions = card.positionRevisions.compactMap { positionByReference[$0] }
            guard cardPositions.count == card.positionRevisions.count else {
                issuesFound.append(issue(.missingRequiredValue, "delegation_position_card.position_revisions", "Every aggregated position must resolve exactly."))
                continue
            }
            let expectedReservations = cardPositions.flatMap(\.reservations)
            let expectedConditions = cardPositions.flatMap(\.conditions)
            if Set(card.reservations) != Set(expectedReservations) {
                issuesFound.append(issue(.inconsistentValue, "delegation_position_card.reservations", "Aggregation must preserve every reservation exactly."))
            }
            if Set(card.conditions) != Set(expectedConditions) {
                issuesFound.append(issue(.inconsistentValue, "delegation_position_card.conditions", "Aggregation must preserve every condition exactly."))
            }
            if cardPositions.contains(where: {
                $0.representedEntityRevision != card.representedEntityRevision
                    || $0.issueRevision != card.issueRevision
            }) {
                issuesFound.append(issue(.inconsistentValue, "delegation_position_card", "A delegation card cannot merge different represented entities or issues."))
            }
        }

        var resolved = additionalDependencies
        resolved += try classifications(actors)
        resolved += try classifications(capacities)
        resolved += try classifications(assignments)
        resolved += try classifications(participants)
        resolved += try classifications(organizations)
        resolved += try classifications(issues)
        resolved += try classifications(positions)
        resolved += try classifications(commitments)
        resolved += try classifications(decisions)
        resolved += try classifications(interventionCards)
        resolved += try classifications(delegationPositionCards)
        let byReference = Dictionary(grouping: resolved, by: \.revisionReference)
        issuesFound += classificationIssues(participants, resolved: byReference)
        issuesFound += classificationIssues(organizations, resolved: byReference)
        issuesFound += classificationIssues(issues, resolved: byReference)
        issuesFound += classificationIssues(positions, resolved: byReference)
        issuesFound += classificationIssues(commitments, resolved: byReference)
        issuesFound += classificationIssues(decisions, resolved: byReference)
        issuesFound += classificationIssues(interventionCards, resolved: byReference)
        issuesFound += classificationIssues(delegationPositionCards, resolved: byReference)

        guard issuesFound.isEmpty else { throw DomainValidationError(issues: issuesFound) }
    }

    private static func validateAll<Object: SemanticRevisionContract>(
        _ values: [Object]
    ) throws {
        for value in values { try value.validate() }
    }

    private static func dictionary<Object: SemanticRevisionContract>(
        _ values: [Object]
    ) throws -> [SemanticRevisionReference: Object] {
        var result: [SemanticRevisionReference: Object] = [:]
        for value in values {
            let reference = try SemanticRevisionReference(
                logicalID: value.revision.logicalID,
                revisionID: value.revision.revisionID
            )
            guard result.updateValue(value, forKey: reference) == nil else {
                throw DomainValidationError(issues: [
                    issue(.duplicateValue, "resolved_objects", "A semantic revision was resolved more than once.")
                ])
            }
        }
        return result
    }

    private static func classifications<Object: SemanticRevisionContract>(
        _ values: [Object]
    ) throws -> [ResolvedDependencyClassification] {
        try values.map(ResolvedDependencyClassification.init(resolving:))
    }

    private static func classificationIssues<Object: SemanticRevisionContract>(
        _ values: [Object],
        resolved: [SemanticRevisionReference: [ResolvedDependencyClassification]]
    ) -> [ValidationIssue] {
        values.flatMap { value in
            let required = Set(
                value.revision.inputRevisions
                    + value.revision.sourceAssetRevisions
                    + value.revision.evidenceRevisions
            )
            var result: [ValidationIssue] = []
            var classifications: [DataClassification] = []
            for reference in required {
                guard let matches = resolved[reference], matches.count == 1,
                      let match = matches.first
                else {
                    result.append(issue(.missingRequiredValue, "resolved_dependencies", "Every exact intelligence dependency must resolve once for classification inheritance."))
                    continue
                }
                classifications.append(match.dataClassification)
            }
            if let requiredClassification = DataClassification.mostRestrictive(classifications),
               value.revision.dataClassification.restrictionRank
                    < requiredClassification.restrictionRank
            {
                result.append(issue(.inconsistentValue, "revision.data_classification", "Derived intelligence cannot be less restrictive than any exact input."))
            }
            return result
        }
    }

    private static func organizationKindMatchesIdentity(
        _ organization: OrganizationV1,
        actor: ActorV1
    ) -> Bool {
        switch (organization.kind, actor.identity) {
        case let (.country, .country(_, countryCode)):
            return organization.countryCode == countryCode
        case (.internationalOrganization, .internationalOrganization),
             (.formalGroup, .formalGroup),
             (.unOrgan, .unOrgan),
             (.unSecretariat, .unSecretariat),
             (.other, .other):
            return organization.countryCode == nil
        default:
            return false
        }
    }

    private static func participantKindMatchesIdentity(
        _ kind: ParticipantKind,
        _ identity: ActorIdentity
    ) -> Bool {
        switch (kind, identity) {
        case (.unidentified, .unidentifiedParticipant):
            true
        case (.person, .person),
             (.chair, .person),
             (.expert, .person),
             (.observer, .person),
             (.briefer, .person),
             (.other, .person),
             (.other, .other):
            true
        default:
            false
        }
    }

    private static func issue(
        _ code: ValidationIssueCode,
        _ path: String,
        _ message: String
    ) -> ValidationIssue {
        ValidationIssue(code: code, path: path, message: message)
    }
}

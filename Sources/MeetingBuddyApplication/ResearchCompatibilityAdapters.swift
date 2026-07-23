import Foundation
import MeetingBuddyDomain

/// Pure read-only projections over accepted immutable Meeting contracts.
///
/// These adapters do not persist, select active revisions, infer authority,
/// mutate payloads, move files, or register production behavior.
public enum ResearchCompatibilityAdapters {
    public static let sourceProjectionVersion = try! VersionedComponent(
        identifier: "blueminutes-source-asset-projection",
        version: "1"
    )

    public static func sharedSource(
        from source: SourceAssetV1,
        canonicalKeyClaim: SourceCanonicalKeyClaim = .unclaimed,
        authority: SourceAuthority,
        completeness: SourceCompleteness
    ) throws -> SharedSourceRef {
        try source.validate()
        let exactRevision = try SemanticRevisionReference(
            logicalID: source.assetID,
            revisionID: source.revision.revisionID
        )
        return try SharedSourceRef(
            sourceRevision: exactRevision,
            sourceKind: .meetingSourceAsset,
            canonicalKeyClaim: canonicalKeyClaim,
            authority: authority,
            completeness: completeness,
            dataClassification: source.revision.dataClassification,
            retentionClass: source.retentionClass,
            contentDigest: source.sourceContentHash,
            externalReference: source.sourceURL,
            projectionProvenance: sourceProjectionVersion
        )
    }

    public static func artifactDescriptor(
        from briefing: FinalBriefingV1
    ) throws -> ArtifactDescriptor {
        try briefing.validate()
        let artifactID = try ArtifactID(validating: briefing.finalBriefingID.canonicalString)
        let exactRevision = try SemanticRevisionReference(
            logicalID: briefing.finalBriefingID,
            revisionID: briefing.revision.revisionID
        )
        return try ArtifactDescriptor(
            artifactID: artifactID,
            kind: .meetingBriefing,
            title: briefing.documentTitle,
            currentVersion: .semanticRevision(exactRevision),
            lifecycleStatus: briefing.revision.lifecycleStatus,
            validationState: briefing.revision.validationState,
            dataClassification: briefing.revision.dataClassification
        )
    }

    public static func artifactDescriptor(
        from comparison: HistoricalComparisonV1,
        title: String = "Historical position comparison"
    ) throws -> ArtifactDescriptor {
        try comparison.validate()
        let artifactID = try ArtifactID(
            validating: comparison.revision.logicalID.canonicalString
        )
        let exactRevision = try SemanticRevisionReference(
            logicalID: comparison.revision.logicalID,
            revisionID: comparison.revision.revisionID
        )
        return try ArtifactDescriptor(
            artifactID: artifactID,
            kind: .historicalComparison,
            title: title,
            currentVersion: .semanticRevision(exactRevision),
            lifecycleStatus: comparison.revision.lifecycleStatus,
            validationState: comparison.revision.validationState,
            dataClassification: comparison.revision.dataClassification
        )
    }
}

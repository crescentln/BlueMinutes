import Foundation

public enum DependencyRole: StableStringValue, Comparable {
    case input
    case sourceAsset
    case evidence
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "input": self = .input
        case "source_asset": self = .sourceAsset
        case "evidence": self = .evidence
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .input: "input"
        case .sourceAsset: "source_asset"
        case .evidence: "evidence"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.encodedValue < rhs.encodedValue
    }
}

/// One exact upstream-to-downstream dependency edge.
public struct DependencyEdge: Codable, Hashable, Sendable, Comparable, DomainValidatable {
    public let upstreamRevision: SemanticRevisionReference
    public let downstreamRevision: SemanticRevisionReference
    public let role: DependencyRole

    public init(
        upstreamRevision: SemanticRevisionReference,
        downstreamRevision: SemanticRevisionReference,
        role: DependencyRole
    ) throws {
        self.upstreamRevision = upstreamRevision
        self.downstreamRevision = downstreamRevision
        self.role = role
        try validate()
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.upstreamRevision != rhs.upstreamRevision {
            return lhs.upstreamRevision < rhs.upstreamRevision
        }
        if lhs.downstreamRevision != rhs.downstreamRevision {
            return lhs.downstreamRevision < rhs.downstreamRevision
        }
        return lhs.role < rhs.role
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = upstreamRevision.validationIssues()
        issues.append(contentsOf: downstreamRevision.validationIssues())
        if upstreamRevision == downstreamRevision {
            issues.append(
                ValidationIssue(
                    code: .inconsistentValue,
                    path: "dependency_edge",
                    message: "A revision cannot depend on itself."
                )
            )
        }
        if !role.isKnown {
            issues.append(
                ValidationIssue(
                    code: .unsupportedValue,
                    path: "dependency_edge.role",
                    message: "The dependency role is not supported by this contract version."
                )
            )
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        upstreamRevision = try container.decode(SemanticRevisionReference.self, forKey: .upstreamRevision)
        downstreamRevision = try container.decode(SemanticRevisionReference.self, forKey: .downstreamRevision)
        role = try container.decode(DependencyRole.self, forKey: .role)
        try validate()
    }

    public static func from<Tag: LogicalObjectIDScope>(
        downstream envelope: RevisionEnvelope<Tag>
    ) throws -> [DependencyEdge] {
        let downstream = try SemanticRevisionReference(
            logicalID: envelope.logicalID,
            revisionID: envelope.revisionID
        )
        var edges: [DependencyEdge] = []
        edges += try envelope.inputRevisions.map {
            try DependencyEdge(upstreamRevision: $0, downstreamRevision: downstream, role: .input)
        }
        edges += try envelope.sourceAssetRevisions.map {
            try DependencyEdge(upstreamRevision: $0, downstreamRevision: downstream, role: .sourceAsset)
        }
        edges += try envelope.evidenceRevisions.map {
            try DependencyEdge(upstreamRevision: $0, downstreamRevision: downstream, role: .evidence)
        }
        return edges.sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case upstreamRevision = "upstream_revision"
        case downstreamRevision = "downstream_revision"
        case role
    }
}

/// Why an exact revision ceased to be a current input.
public enum InvalidationReason: Codable, Hashable, Sendable, DomainValidatable {
    case activePublishedRevisionReplaced(
        previous: SemanticRevisionReference,
        replacement: SemanticRevisionReference
    )
    case upstreamRevisionInvalidated(revision: SemanticRevisionReference)
    case sourceTimelineChangedOrUnverified(
        previous: SemanticRevisionReference,
        replacement: SemanticRevisionReference?
    )

    private enum Kind: String, Codable {
        case activePublishedRevisionReplaced = "active_published_revision_replaced"
        case upstreamRevisionInvalidated = "upstream_revision_invalidated"
        case sourceTimelineChangedOrUnverified = "source_timeline_changed_or_unverified"
    }

    public var rootRevision: SemanticRevisionReference {
        switch self {
        case let .activePublishedRevisionReplaced(previous, _),
             let .sourceTimelineChangedOrUnverified(previous, _):
            previous
        case let .upstreamRevisionInvalidated(revision):
            revision
        }
    }

    public var replacementRevision: SemanticRevisionReference? {
        switch self {
        case let .activePublishedRevisionReplaced(_, replacement):
            replacement
        case let .sourceTimelineChangedOrUnverified(_, replacement):
            replacement
        case .upstreamRevisionInvalidated:
            nil
        }
    }

    public static func activeReplacement(
        _ change: ActivePublishedRevisionChange
    ) throws -> InvalidationReason? {
        try change.validate()
        guard let previous = change.previous, previous != change.replacement else { return nil }
        return try InvalidationReason.activePublishedRevisionReplaced(
            previous: previous,
            replacement: change.replacement
        ).validated()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = rootRevision.validationIssues()
        if let replacementRevision {
            issues.append(contentsOf: replacementRevision.validationIssues())
        }
        switch self {
        case let .activePublishedRevisionReplaced(previous, replacement):
            if previous.objectType != replacement.objectType {
                issues.append(Self.issue(.inconsistentValue, "replacement.object_type", "An active replacement must preserve object type."))
            }
            if previous.logicalID != replacement.logicalID {
                issues.append(Self.issue(.inconsistentValue, "replacement.logical_id", "An active replacement must preserve logical object identity."))
            }
            if previous.revisionID == replacement.revisionID {
                issues.append(Self.issue(.inconsistentValue, "replacement.revision_id", "An active replacement must select a different revision."))
            }
        case .upstreamRevisionInvalidated:
            break
        case let .sourceTimelineChangedOrUnverified(previous, replacement):
            if previous.objectType != .sourceAsset {
                issues.append(Self.issue(.inconsistentValue, "previous.object_type", "A timeline invalidation must originate from a SourceAsset revision."))
            }
            if let replacement {
                if replacement.objectType != .sourceAsset {
                    issues.append(Self.issue(.inconsistentValue, "replacement.object_type", "A timeline replacement must be a SourceAsset revision."))
                }
                if previous.logicalID != replacement.logicalID {
                    issues.append(Self.issue(.inconsistentValue, "replacement.logical_id", "A timeline replacement must preserve source logical identity."))
                }
                if previous.revisionID == replacement.revisionID {
                    issues.append(Self.issue(.inconsistentValue, "replacement.revision_id", "A timeline replacement must select a different revision."))
                }
            }
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .activePublishedRevisionReplaced:
            self = .activePublishedRevisionReplaced(
                previous: try container.decode(SemanticRevisionReference.self, forKey: .previous),
                replacement: try container.decode(SemanticRevisionReference.self, forKey: .replacement)
            )
        case .upstreamRevisionInvalidated:
            self = .upstreamRevisionInvalidated(
                revision: try container.decode(SemanticRevisionReference.self, forKey: .revision)
            )
        case .sourceTimelineChangedOrUnverified:
            self = .sourceTimelineChangedOrUnverified(
                previous: try container.decode(SemanticRevisionReference.self, forKey: .previous),
                replacement: try container.decodeIfPresent(SemanticRevisionReference.self, forKey: .replacement)
            )
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .activePublishedRevisionReplaced(previous, replacement):
            try container.encode(Kind.activePublishedRevisionReplaced, forKey: .kind)
            try container.encode(previous, forKey: .previous)
            try container.encode(replacement, forKey: .replacement)
        case let .upstreamRevisionInvalidated(revision):
            try container.encode(Kind.upstreamRevisionInvalidated, forKey: .kind)
            try container.encode(revision, forKey: .revision)
        case let .sourceTimelineChangedOrUnverified(previous, replacement):
            try container.encode(Kind.sourceTimelineChangedOrUnverified, forKey: .kind)
            try container.encode(previous, forKey: .previous)
            try container.encodeIfPresent(replacement, forKey: .replacement)
        }
    }

    private func validated() throws -> Self {
        try validate()
        return self
    }

    private static func issue(_ code: ValidationIssueCode, _ path: String, _ message: String) -> ValidationIssue {
        ValidationIssue(code: code, path: path, message: message)
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case previous
        case replacement
        case revision
    }
}

public enum StalePlanAction: StableStringValue {
    case recompute
    case preserveAndReview
    case blocked
    case unrecognized(String)

    public init(encodedValue: String) {
        switch encodedValue {
        case "recompute": self = .recompute
        case "preserve_and_review": self = .preserveAndReview
        case "blocked": self = .blocked
        default: self = .unrecognized(encodedValue)
        }
    }

    public var encodedValue: String {
        switch self {
        case .recompute: "recompute"
        case .preserveAndReview: "preserve_and_review"
        case .blocked: "blocked"
        case let .unrecognized(value): value
        }
    }

    public var isKnown: Bool {
        if case .unrecognized = self { return false }
        return true
    }
}

public struct RevisionHandlingPolicy: Codable, Hashable, Sendable, DomainValidatable {
    public let revision: SemanticRevisionReference
    public let action: StalePlanAction

    public init(revision: SemanticRevisionReference, action: StalePlanAction) throws {
        self.revision = revision
        self.action = action
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = revision.validationIssues()
        if !action.isKnown {
            issues.append(
                ValidationIssue(
                    code: .unsupportedValue,
                    path: "revision_handling_policy.action",
                    message: "The stale-plan action is not supported by this contract version."
                )
            )
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = try container.decode(SemanticRevisionReference.self, forKey: .revision)
        action = try container.decode(StalePlanAction.self, forKey: .action)
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case action
    }
}

public struct StaleReason: Codable, Hashable, Sendable, DomainValidatable {
    public let invalidation: InvalidationReason
    public let dependencyPath: [DependencyEdge]

    public init(invalidation: InvalidationReason, dependencyPath: [DependencyEdge]) throws {
        self.invalidation = invalidation
        self.dependencyPath = dependencyPath
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = invalidation.validationIssues()
        if dependencyPath.isEmpty {
            issues.append(
                ValidationIssue(
                    code: .missingRequiredValue,
                    path: "dependency_path",
                    message: "A stale reason requires a causal dependency path."
                )
            )
            return issues
        }
        for edge in dependencyPath { issues.append(contentsOf: edge.validationIssues()) }
        issues.append(contentsOf: duplicateIssues(in: dependencyPath, path: "dependency_path"))
        if let first = dependencyPath.first {
            issues.append(
                contentsOf: duplicateIssues(
                    in: [first.upstreamRevision] + dependencyPath.map(\.downstreamRevision),
                    path: "dependency_path.revisions"
                )
            )
        }
        if dependencyPath.first?.upstreamRevision != invalidation.rootRevision {
            issues.append(
                ValidationIssue(
                    code: .inconsistentValue,
                    path: "dependency_path",
                    message: "A stale path must begin at the invalidated root revision."
                )
            )
        }
        for pair in zip(dependencyPath, dependencyPath.dropFirst())
            where pair.0.downstreamRevision != pair.1.upstreamRevision
        {
            issues.append(
                ValidationIssue(
                    code: .inconsistentValue,
                    path: "dependency_path",
                    message: "Every stale-path edge must connect to the next edge."
                )
            )
            break
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        invalidation = try container.decode(InvalidationReason.self, forKey: .invalidation)
        dependencyPath = try container.decode([DependencyEdge].self, forKey: .dependencyPath)
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case invalidation
        case dependencyPath = "dependency_path"
    }
}

public struct StaleMark: Codable, Hashable, Sendable, Comparable, DomainValidatable {
    public let affectedRevision: SemanticRevisionReference
    public let reason: StaleReason
    public let action: StalePlanAction

    public init(
        affectedRevision: SemanticRevisionReference,
        reason: StaleReason,
        action: StalePlanAction
    ) throws {
        self.affectedRevision = affectedRevision
        self.reason = reason
        self.action = action
        try validate()
    }

    public var minimumDependencyDepth: UInt32 {
        UInt32(reason.dependencyPath.count)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.minimumDependencyDepth != rhs.minimumDependencyDepth {
            return lhs.minimumDependencyDepth < rhs.minimumDependencyDepth
        }
        return lhs.affectedRevision < rhs.affectedRevision
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = affectedRevision.validationIssues()
        issues.append(contentsOf: reason.validationIssues())
        if reason.dependencyPath.last?.downstreamRevision != affectedRevision {
            issues.append(
                ValidationIssue(
                    code: .inconsistentValue,
                    path: "affected_revision",
                    message: "The stale path must terminate at the affected revision."
                )
            )
        }
        if !action.isKnown {
            issues.append(
                ValidationIssue(
                    code: .unsupportedValue,
                    path: "action",
                    message: "The stale-plan action is not supported by this contract version."
                )
            )
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        affectedRevision = try container.decode(SemanticRevisionReference.self, forKey: .affectedRevision)
        reason = try container.decode(StaleReason.self, forKey: .reason)
        action = try container.decode(StalePlanAction.self, forKey: .action)
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case affectedRevision = "affected_revision"
        case reason
        case action
    }
}

public struct StalePlan: Codable, Hashable, Sendable, DomainValidatable {
    public let invalidation: InvalidationReason?
    public let marks: [StaleMark]

    public init(invalidation: InvalidationReason?, marks: [StaleMark]) throws {
        self.invalidation = invalidation
        self.marks = marks.sorted()
        try validate()
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues = invalidation?.validationIssues() ?? []
        for mark in marks { issues.append(contentsOf: mark.validationIssues()) }
        issues.append(contentsOf: duplicateIssues(in: marks.map(\.affectedRevision), path: "marks.affected_revision"))
        if invalidation == nil, !marks.isEmpty {
            issues.append(
                ValidationIssue(
                    code: .inconsistentValue,
                    path: "marks",
                    message: "A no-op or initial publication cannot contain stale marks."
                )
            )
        }
        if let invalidation,
           marks.contains(where: { $0.reason.invalidation != invalidation })
        {
            issues.append(
                ValidationIssue(
                    code: .inconsistentValue,
                    path: "marks.reason.invalidation",
                    message: "Every stale mark must share the plan's invalidation root."
                )
            )
        }
        return issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        invalidation = try container.decodeIfPresent(InvalidationReason.self, forKey: .invalidation)
        marks = try container.decode([StaleMark].self, forKey: .marks).sorted()
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case invalidation
        case marks
    }
}

/// Pure, side-effect-free stale planning. It never mutates a semantic revision.
public enum DeterministicStalePlanner {
    public static func plan(
        for change: ActivePublishedRevisionChange,
        dependencyEdges: [DependencyEdge],
        handlingPolicies: [RevisionHandlingPolicy] = []
    ) throws -> StalePlan {
        try change.validate()
        for edge in dependencyEdges { try edge.validate() }
        let duplicateEdgeIssues = duplicateIssues(in: dependencyEdges, path: "dependency_edges")
        guard duplicateEdgeIssues.isEmpty else {
            throw DomainValidationError(issues: duplicateEdgeIssues)
        }
        for policy in handlingPolicies { try policy.validate() }
        let duplicatePolicyIssues = duplicateIssues(
            in: handlingPolicies.map(\.revision),
            path: "handling_policies.revision"
        )
        guard duplicatePolicyIssues.isEmpty else {
            throw DomainValidationError(issues: duplicatePolicyIssues)
        }
        try rejectCycles(in: dependencyEdges)

        guard let invalidation = try InvalidationReason.activeReplacement(change) else {
            return try StalePlan(invalidation: nil, marks: [])
        }

        var adjacency: [SemanticRevisionReference: [DependencyEdge]] = [:]
        for edge in dependencyEdges.sorted() {
            adjacency[edge.upstreamRevision, default: []].append(edge)
        }
        let actions = Dictionary(uniqueKeysWithValues: handlingPolicies.map { ($0.revision, $0.action) })
        var paths: [SemanticRevisionReference: [DependencyEdge]] = [invalidation.rootRevision: []]
        var queue: [SemanticRevisionReference] = [invalidation.rootRevision]
        var index = 0

        while index < queue.count {
            let current = queue[index]
            index += 1
            let currentPath = paths[current] ?? []
            for edge in adjacency[current, default: []].sorted() {
                guard paths[edge.downstreamRevision] == nil else { continue }
                paths[edge.downstreamRevision] = currentPath + [edge]
                queue.append(edge.downstreamRevision)
            }
        }

        if let replacement = invalidation.replacementRevision,
           paths[replacement] != nil
        {
            throw DomainValidationError(
                issues: [
                    ValidationIssue(
                        code: .inconsistentValue,
                        path: "dependency_edges",
                        message: "The replacement active revision cannot depend on the revision it replaces."
                    )
                ]
            )
        }

        let marks = try paths.compactMap { reference, path -> StaleMark? in
            guard reference != invalidation.rootRevision, !path.isEmpty else { return nil }
            return try StaleMark(
                affectedRevision: reference,
                reason: StaleReason(invalidation: invalidation, dependencyPath: path),
                action: actions[reference] ?? .preserveAndReview
            )
        }.sorted()
        return try StalePlan(invalidation: invalidation, marks: marks)
    }

    private static func rejectCycles(in edges: [DependencyEdge]) throws {
        let nodes = Set(edges.flatMap { [$0.upstreamRevision, $0.downstreamRevision] })
        var indegree = Dictionary(uniqueKeysWithValues: nodes.map { ($0, 0) })
        var adjacency: [SemanticRevisionReference: [SemanticRevisionReference]] = [:]
        for edge in edges {
            indegree[edge.downstreamRevision, default: 0] += 1
            adjacency[edge.upstreamRevision, default: []].append(edge.downstreamRevision)
        }
        var queue = indegree.compactMap { $0.value == 0 ? $0.key : nil }.sorted()
        var visited = 0
        while !queue.isEmpty {
            let node = queue.removeFirst()
            visited += 1
            for downstream in adjacency[node, default: []].sorted() {
                indegree[downstream, default: 0] -= 1
                if indegree[downstream] == 0 {
                    queue.append(downstream)
                    queue.sort()
                }
            }
        }
        guard visited == nodes.count else {
            throw DomainValidationError(
                issues: [
                    ValidationIssue(
                        code: .inconsistentValue,
                        path: "dependency_edges",
                        message: "The dependency graph must be acyclic."
                    )
                ]
            )
        }
    }
}

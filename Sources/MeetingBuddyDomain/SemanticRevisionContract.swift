/// A concrete immutable semantic revision with a verifiable content hash.
public protocol SemanticRevisionContract: Codable, Hashable, Sendable, DomainValidatable {
    associatedtype ObjectIDTag: LogicalObjectIDScope

    var revision: RevisionEnvelope<ObjectIDTag> { get }
    func calculatedSemanticContentHash() throws -> ContentDigest
}

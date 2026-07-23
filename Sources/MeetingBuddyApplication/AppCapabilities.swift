/// An immutable, composition-owned snapshot of future Research integration
/// capabilities. Phase 1 does not persist, decode, or remotely configure it.
public struct AppCapabilities: Hashable, Sendable {
    public let research: Bool
    public let transcriptSourceResolution: Bool
    public let sharedObjectStore: Bool
    public let conversationPersistence: Bool

    public init() {
        self.init(
            research: false,
            transcriptSourceResolution: false,
            sharedObjectStore: false,
            conversationPersistence: false
        )
    }

    public init(
        research: Bool,
        transcriptSourceResolution: Bool,
        sharedObjectStore: Bool,
        conversationPersistence: Bool
    ) {
        self.research = research
        self.transcriptSourceResolution = transcriptSourceResolution
        self.sharedObjectStore = sharedObjectStore
        self.conversationPersistence = conversationPersistence
    }

    public var canonicalDescription: String {
        [
            "research=\(research)",
            "transcript_source_resolution=\(transcriptSourceResolution)",
            "shared_object_store=\(sharedObjectStore)",
            "conversation_persistence=\(conversationPersistence)"
        ].joined(separator: ",")
    }
}

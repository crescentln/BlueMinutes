import UniformTypeIdentifiers

enum LocalFileImporterPurpose: Equatable, Sendable {
    case workspace
    case media

    var allowedContentTypes: [UTType] {
        switch self {
        case .workspace:
            [.folder]
        case .media:
            [.audio, .movie]
        }
    }
}

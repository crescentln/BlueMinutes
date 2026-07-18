import Foundation
import MeetingBuddyApplication

enum WorkspacePathSecurity {
    static func confinedURL(
        _ url: URL,
        within root: URL,
        allowMissingLeaf: Bool = false
    ) throws -> URL {
        let fileManager = FileManager.default
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let exists = fileManager.fileExists(atPath: url.path)
        if exists {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw WorkspaceContractError.symbolicLinkNotAllowed(url.path)
            }
        }

        let candidate: URL
        if allowMissingLeaf, !exists {
            let parent = url.deletingLastPathComponent()
                .resolvingSymlinksInPath()
                .standardizedFileURL
            candidate = parent.appendingPathComponent(url.lastPathComponent).standardizedFileURL
        } else {
            candidate = url.resolvingSymlinksInPath().standardizedFileURL
        }
        guard candidate.path == canonicalRoot.path
                || candidate.path.hasPrefix(canonicalRoot.path + "/")
        else {
            throw WorkspaceContractError.pathEscapesWorkspace(url.path)
        }
        return candidate
    }

    static func createPrivateDirectory(
        _ url: URL,
        within root: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let confined = try confinedURL(url, within: root, allowMissingLeaf: true)
        try fileManager.createDirectory(at: confined, withIntermediateDirectories: true)
        let resolved = try confinedURL(confined, within: root)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: resolved.path)
        return resolved
    }
}

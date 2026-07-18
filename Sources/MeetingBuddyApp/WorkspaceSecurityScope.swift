import Foundation

@MainActor
final class WorkspaceSecurityScope {
    private static let bookmarkKey = "meetingbuddy.workspace.security-scoped-bookmark.v1"

    private var activeURL: URL?
    private var didStartSecurityScope = false

    deinit {
        if didStartSecurityScope {
            activeURL?.stopAccessingSecurityScopedResource()
        }
    }

    func activate(_ url: URL) throws -> URL {
        release()
        let standardized = url.standardizedFileURL
        let didStart = standardized.startAccessingSecurityScopedResource()
        do {
            let bookmark = try standardized.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            activeURL = standardized
            didStartSecurityScope = didStart
            return standardized
        } catch {
            if didStart {
                standardized.stopAccessingSecurityScopedResource()
            }
            throw AppWorkflowError.workspaceAuthorizationFailed
        }
    }

    func restore() throws -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else {
            return nil
        }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ).standardizedFileURL
            guard !isStale else {
                UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
                return nil
            }
            release()
            didStartSecurityScope = url.startAccessingSecurityScopedResource()
            activeURL = url
            return url
        } catch {
            UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
            throw AppWorkflowError.workspaceAuthorizationFailed
        }
    }

    func release() {
        if didStartSecurityScope {
            activeURL?.stopAccessingSecurityScopedResource()
        }
        activeURL = nil
        didStartSecurityScope = false
    }

    func forget() {
        release()
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
    }
}

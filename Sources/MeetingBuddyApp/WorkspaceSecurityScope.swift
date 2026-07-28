import Foundation

@MainActor
final class WorkspaceSecurityScope {
    private static let bookmarkKey = "meetingbuddy.workspace.security-scoped-bookmark.v1"

    struct Candidate {
        let url: URL
        let bookmark: Data
        let didStartSecurityScope: Bool
    }

    private var activeURL: URL?
    private var didStartSecurityScope = false

    deinit {
        if didStartSecurityScope {
            activeURL?.stopAccessingSecurityScopedResource()
        }
    }

    /// Opens a candidate scope without changing the current scope or bookmark.
    ///
    /// The caller must either commit after the candidate workspace passes all
    /// recovery checks or discard on every failure path.
    func prepare(_ url: URL) throws -> Candidate {
        let standardized = url.standardizedFileURL
        let didStart = standardized.startAccessingSecurityScopedResource()
        do {
            let bookmark = try standardized.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return Candidate(
                url: standardized,
                bookmark: bookmark,
                didStartSecurityScope: didStart
            )
        } catch {
            if didStart {
                standardized.stopAccessingSecurityScopedResource()
            }
            throw AppWorkflowError.workspaceAuthorizationFailed
        }
    }

    /// Atomically makes a validated candidate the restorable workspace.
    func commit(_ candidate: Candidate) {
        let previousURL = activeURL
        let previousDidStart = didStartSecurityScope
        UserDefaults.standard.set(
            candidate.bookmark,
            forKey: Self.bookmarkKey
        )
        activeURL = candidate.url
        didStartSecurityScope =
            candidate.didStartSecurityScope
        if previousDidStart {
            previousURL?
                .stopAccessingSecurityScopedResource()
        }
    }

    /// Closes a failed candidate without disturbing the active workspace.
    func discard(_ candidate: Candidate) {
        if candidate.didStartSecurityScope {
            candidate.url
                .stopAccessingSecurityScopedResource()
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

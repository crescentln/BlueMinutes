import Foundation
import MeetingBuddyApplication

struct WorkspaceLayout: Hashable, Sendable {
    let root: URL
    let meetings: URL
    let models: URL
    let database: URL
    let indexes: URL
    let backups: URL
    let logs: URL
    let tasks: URL
    let temporary: URL
    let trash: URL
    let manifests: URL
    let workspaceManifest: URL
    let databaseFile: URL
}

/// Opaque local-workspace capability returned by `LocalWorkspaceService`.
///
/// Only the persistence module can resolve its concrete filesystem layout.
/// Feature, provider, and automation targets receive application services,
/// never unrestricted workspace URLs.
public struct LocalWorkspaceDescriptor: Hashable, Sendable {
    public let manifest: WorkspaceManifest
    let layout: WorkspaceLayout

    init(manifest: WorkspaceManifest, layout: WorkspaceLayout) {
        self.manifest = manifest
        self.layout = layout
    }
}

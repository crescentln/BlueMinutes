import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public struct LocalWorkspaceService: WorkspaceService, @unchecked Sendable {
    public static let manifestFilename = "workspace_manifest.json"
    public static let databaseRelativePath = try! WorkspaceRelativePath("Database/meetingbuddy.sqlite")

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func createWorkspace(
        at root: URL,
        workspaceID: WorkspaceID,
        createdAt: UTCInstant
    ) throws -> LocalWorkspaceDescriptor {
        let standardizedRoot = root.standardizedFileURL
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: standardizedRoot.path, isDirectory: &isDirectory) {
            let rootValues = try standardizedRoot.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard rootValues.isSymbolicLink != true else {
                throw WorkspaceContractError.symbolicLinkNotAllowed(standardizedRoot.path)
            }
            guard isDirectory.boolValue else {
                throw WorkspaceContractError.invalidWorkspaceRoot(
                    "The selected workspace root is not a directory."
                )
            }
            let contents = try fileManager.contentsOfDirectory(
                at: standardizedRoot,
                includingPropertiesForKeys: nil,
                options: []
            )
            let manifestURL = standardizedRoot.appendingPathComponent(Self.manifestFilename)
            if fileManager.fileExists(atPath: manifestURL.path) {
                let existing = try openWorkspace(at: standardizedRoot)
                guard existing.manifest.workspaceID == workspaceID else {
                    throw WorkspaceContractError.workspaceManifestMismatch(
                        "The existing workspace has a different workspace ID."
                    )
                }
                return existing
            }
            guard contents.isEmpty else {
                throw WorkspaceContractError.invalidWorkspaceRoot(
                    "A new workspace root must be empty or already contain a MeetingBuddy manifest."
                )
            }
        } else {
            try fileManager.createDirectory(
                at: standardizedRoot,
                withIntermediateDirectories: true
            )
        }

        let canonicalRoot = standardizedRoot.resolvingSymlinksInPath().standardizedFileURL
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: canonicalRoot.path
        )
        let layout = try makeLayout(root: canonicalRoot)
        for directory in managedDirectories(in: layout) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        }

        let manifest = try WorkspaceManifest(
            workspaceID: workspaceID,
            createdAt: createdAt,
            databasePath: Self.databaseRelativePath
        )
        let data = try canonicalJSON(manifest)
        try data.write(to: layout.workspaceManifest, options: [.atomic])
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: layout.workspaceManifest.path
        )
        return LocalWorkspaceDescriptor(manifest: manifest, layout: layout)
    }

    public func openWorkspace(at root: URL) throws -> LocalWorkspaceDescriptor {
        let suppliedRoot = root.standardizedFileURL
        let rootValues = try suppliedRoot.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard rootValues.isSymbolicLink != true else {
            throw WorkspaceContractError.symbolicLinkNotAllowed(suppliedRoot.path)
        }
        let canonicalRoot = root.standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let layout = try makeLayout(root: canonicalRoot)
        guard fileManager.fileExists(atPath: layout.workspaceManifest.path) else {
            throw WorkspaceContractError.workspaceManifestMissing
        }
        let manifestURL = try WorkspacePathSecurity.confinedURL(
            layout.workspaceManifest,
            within: canonicalRoot
        )
        let manifestValues = try manifestURL.resourceValues(
            forKeys: [.isRegularFileKey, .fileSizeKey]
        )
        guard manifestValues.isRegularFile == true,
              let manifestSize = manifestValues.fileSize,
              manifestSize > 0,
              manifestSize <= 65_536
        else {
            throw WorkspaceContractError.workspaceManifestMismatch(
                "The workspace manifest is not a bounded regular file."
            )
        }
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(WorkspaceManifest.self, from: data)
        guard manifest.databasePath == Self.databaseRelativePath else {
            throw WorkspaceContractError.workspaceManifestMismatch(
                "The database path does not match workspace format version 1."
            )
        }
        for directory in managedDirectories(in: layout) {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                throw WorkspaceContractError.workspaceManifestMismatch(
                    "Required workspace directory is missing: \(directory.lastPathComponent)."
                )
            }
            _ = try WorkspacePathSecurity.confinedURL(directory, within: canonicalRoot)
        }
        return LocalWorkspaceDescriptor(manifest: manifest, layout: layout)
    }

    private func makeLayout(root: URL) throws -> WorkspaceLayout {
        guard root.isFileURL, root.path != "/" else {
            throw WorkspaceContractError.invalidWorkspaceRoot(
                "A workspace requires a specific local directory."
            )
        }
        let layout = WorkspaceLayout(
            root: root,
            meetings: root.appendingPathComponent("Meetings", isDirectory: true),
            models: root.appendingPathComponent("Models", isDirectory: true),
            database: root.appendingPathComponent("Database", isDirectory: true),
            indexes: root.appendingPathComponent("Indexes", isDirectory: true),
            backups: root.appendingPathComponent("Backups", isDirectory: true),
            logs: root.appendingPathComponent("Logs", isDirectory: true),
            tasks: root.appendingPathComponent(".tasks", isDirectory: true),
            temporary: root.appendingPathComponent(".temp", isDirectory: true),
            trash: root.appendingPathComponent(".Trash", isDirectory: true),
            manifests: root.appendingPathComponent("manifests", isDirectory: true),
            workspaceManifest: root.appendingPathComponent(Self.manifestFilename),
            databaseFile: root.appendingPathComponent(Self.databaseRelativePath.rawValue)
        )
        try ensureConfined(layout.databaseFile, to: root, allowMissingLeaf: true)
        return layout
    }

    private func managedDirectories(in layout: WorkspaceLayout) -> [URL] {
        [
            layout.meetings,
            layout.models,
            layout.database,
            layout.indexes,
            layout.backups,
            layout.logs,
            layout.tasks,
            layout.temporary,
            layout.trash,
            layout.manifests
        ]
    }

    private func ensureConfined(
        _ url: URL,
        to root: URL,
        allowMissingLeaf: Bool = false
    ) throws {
        let candidate: URL
        if allowMissingLeaf, !fileManager.fileExists(atPath: url.path) {
            candidate = url.deletingLastPathComponent()
                .resolvingSymlinksInPath()
                .appendingPathComponent(url.lastPathComponent)
                .standardizedFileURL
        } else {
            candidate = url.resolvingSymlinksInPath().standardizedFileURL
        }
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        guard candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") else {
            throw WorkspaceContractError.pathEscapesWorkspace(url.path)
        }
    }

    private func canonicalJSON<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

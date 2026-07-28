import Foundation

public enum CodexRuntimeConfigurationError: Error, Equatable, Sendable {
    case invalidStorageRoot
    case unsafeStorageItem
    case storageLimitExceeded
    case missingKeychainEnvironment
    case configurationWriteFailed
}

public struct CodexRuntimeProcessConfiguration: Hashable, Sendable {
    public let runtimeVersion: String
    public let runtimeSource: CodexRuntimeSource
    public let contextToolEnabled: Bool

    let executableURL: URL
    let executableSHA256: String
    let arguments: [String]
    let environment: [String: String]
    let codexHomeURL: URL
    let disposableWorkingDirectoryURL: URL
    let disposableTemporaryDirectoryURL: URL

    fileprivate init(
        authorization: CodexRuntimeLaunchAuthorization,
        environment: [String: String],
        codexHomeURL: URL,
        disposableWorkingDirectoryURL: URL,
        disposableTemporaryDirectoryURL: URL,
        contextToolEnabled: Bool
    ) {
        runtimeVersion = authorization.descriptor.version
        runtimeSource = authorization.descriptor.source
        self.contextToolEnabled = contextToolEnabled
        executableURL = authorization.descriptor.executableURL
        executableSHA256 =
            authorization.descriptor.executableSHA256
        arguments = ["app-server", "--strict-config", "--stdio"]
        self.environment = environment
        self.codexHomeURL = codexHomeURL
        self.disposableWorkingDirectoryURL =
            disposableWorkingDirectoryURL
        self.disposableTemporaryDirectoryURL =
            disposableTemporaryDirectoryURL
    }
}

/// Owns one private, bounded Codex runtime area. Meeting text is never written
/// into the disposable working directory. The private CODEX_HOME is ephemeral:
/// it is purged before every connection and after a confirmed process exit.
public actor CodexRuntimeEnvironmentManager {
    public static let maximumStorageBytes: UInt64 = 128 * 1_024 * 1_024

    public static let strictConfiguration = """
    approval_policy = "never"
    sandbox_mode = "read-only"
    web_search = "disabled"
    forced_login_method = "chatgpt"
    cli_auth_credentials_store = "keyring"
    allow_login_shell = false
    check_for_update_on_startup = false
    file_opener = "none"
    include_apps_instructions = false
    include_collaboration_mode_instructions = false
    include_environment_context = false
    include_permissions_instructions = false

    [analytics]
    enabled = false

    [feedback]
    enabled = false

    [history]
    persistence = "none"

    [shell_environment_policy]
    inherit = "none"

    [tools]
    web_search = false

    [apps._default]
    enabled = false
    destructive_enabled = false
    open_world_enabled = false

    [features]
    apps = false
    auth_elicitation = false
    browser_use = false
    browser_use_external = false
    browser_use_full_cdp_access = false
    code_mode = false
    code_mode_buffered_exec = false
    code_mode_host = false
    code_mode_only = false
    computer_use = false
    default_mode_request_user_input = false
    deferred_executor = false
    enable_mcp_apps = false
    executor_capability_discovery = false
    external_agent_memory_import = false
    goals = false
    guardian_approval = false
    hooks = false
    image_generation = false
    in_app_browser = false
    memories = false
    mentions_v2 = false
    multi_agent = false
    multi_agent_v2 = false
    network_proxy = false
    plugin_sharing = false
    plugins = false
    realtime_conversation = false
    remote_plugin = false
    request_permissions_tool = false
    shell_snapshot = false
    shell_tool = false
    skill_mcp_dependency_install = false
    skill_search = false
    standalone_web_search = false
    tool_call_mcp_elicitation = false
    tool_suggest = false
    unified_exec = false
    unified_exec_zsh_fork = false
    workspace_dependencies = false
    """

    private let rootURL: URL
    private let sourceEnvironment: [String: String]
    private let fileManager: FileManager

    public init(
        rootURL: URL,
        sourceEnvironment: [String: String] =
            ProcessInfo.processInfo.environment
    ) throws {
        let standardized = rootURL.standardizedFileURL
        guard standardized.isFileURL,
              standardized.path.hasPrefix("/"),
              standardized.path != "/",
              standardized.path != NSHomeDirectory()
        else {
            throw CodexRuntimeConfigurationError.invalidStorageRoot
        }
        self.rootURL = standardized
        self.sourceEnvironment = sourceEnvironment
        fileManager = FileManager()
    }

    public func prepare(
        authorization: CodexRuntimeLaunchAuthorization,
        contextToolEnabled: Bool
    ) throws -> CodexRuntimeProcessConfiguration {
        let codexHome = rootURL.appendingPathComponent(
            "home",
            isDirectory: true
        )
        let sessions = rootURL.appendingPathComponent(
            "sessions",
            isDirectory: true
        )
        let temporary = rootURL.appendingPathComponent(
            "tmp",
            isDirectory: true
        )
        try ensurePrivateDirectory(rootURL)
        try removeRuntimeChildren([
            codexHome,
            sessions,
            temporary
        ])
        try ensurePrivateDirectory(codexHome)
        try ensurePrivateDirectory(sessions)
        try ensurePrivateDirectory(temporary)
        guard try storageUsageBytes() <= Self.maximumStorageBytes else {
            throw CodexRuntimeConfigurationError.storageLimitExceeded
        }

        let configURL = codexHome.appendingPathComponent(
            "config.toml",
            isDirectory: false
        )
        try writeStrictConfiguration(to: configURL)

        let sessionID = UUID().uuidString.lowercased()
        let workingDirectory = sessions.appendingPathComponent(
            sessionID,
            isDirectory: true
        )
        let temporaryDirectory = temporary.appendingPathComponent(
            sessionID,
            isDirectory: true
        )
        try ensurePrivateDirectory(workingDirectory)
        try ensurePrivateDirectory(temporaryDirectory)
        guard try fileManager.contentsOfDirectory(
            at: workingDirectory,
            includingPropertiesForKeys: nil
        ).isEmpty else {
            throw CodexRuntimeConfigurationError.unsafeStorageItem
        }

        let environment = try makeEnvironment(
            codexHome: codexHome,
            temporaryDirectory: temporaryDirectory
        )
        return CodexRuntimeProcessConfiguration(
            authorization: authorization,
            environment: environment,
            codexHomeURL: codexHome,
            disposableWorkingDirectoryURL: workingDirectory,
            disposableTemporaryDirectoryURL: temporaryDirectory,
            contextToolEnabled: contextToolEnabled
        )
    }

    public func storageUsageBytes() throws -> UInt64 {
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return 0
        }
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileAllocatedSizeKey,
            .fileSizeKey
        ]
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants]
        ) else {
            throw CodexRuntimeConfigurationError.unsafeStorageItem
        }
        var total: UInt64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else {
                throw CodexRuntimeConfigurationError.unsafeStorageItem
            }
            if values.isRegularFile == true {
                let size = values.fileAllocatedSize ?? values.fileSize ?? 0
                guard size >= 0,
                      total <= UInt64.max - UInt64(size)
                else {
                    throw CodexRuntimeConfigurationError
                        .storageLimitExceeded
                }
                total += UInt64(size)
                if total > Self.maximumStorageBytes {
                    return total
                }
            }
        }
        return total
    }

    public func removeDisposableDirectories(
        for configuration: CodexRuntimeProcessConfiguration
    ) throws {
        for url in [
            configuration.disposableWorkingDirectoryURL,
            configuration.disposableTemporaryDirectoryURL
        ] {
            let standardized = url.standardizedFileURL
            guard standardized.path.hasPrefix(rootURL.path + "/"),
                  standardized.path != rootURL.path
            else {
                throw CodexRuntimeConfigurationError.unsafeStorageItem
            }
            if fileManager.fileExists(atPath: standardized.path) {
                try fileManager.removeItem(at: standardized)
            }
        }
    }

    public func removePrivateRuntimeState(
        for configuration: CodexRuntimeProcessConfiguration
    ) throws {
        try removeRuntimeChildren([
            configuration.codexHomeURL,
            rootURL.appendingPathComponent(
                "sessions",
                isDirectory: true
            ),
            rootURL.appendingPathComponent(
                "tmp",
                isDirectory: true
            )
        ])
    }

    private func makeEnvironment(
        codexHome: URL,
        temporaryDirectory: URL
    ) throws -> [String: String] {
        guard let realHome = sourceEnvironment["HOME"],
              realHome.hasPrefix("/"),
              !realHome.isEmpty,
              let user = sourceEnvironment["USER"],
              !user.isEmpty,
              let logName = sourceEnvironment["LOGNAME"],
              !logName.isEmpty
        else {
            throw CodexRuntimeConfigurationError
                .missingKeychainEnvironment
        }
        return [
            "CODEX_HOME": codexHome.path,
            "HOME": realHome,
            "LANG": "en_US.UTF-8",
            "LOGNAME": logName,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": temporaryDirectory.path + "/",
            "USER": user
        ]
    }

    private func ensurePrivateDirectory(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            let values = try url.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard values.isDirectory == true,
                  values.isSymbolicLink != true
            else {
                throw CodexRuntimeConfigurationError.unsafeStorageItem
            }
        } else {
            do {
                try fileManager.createDirectory(
                    at: url,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                throw CodexRuntimeConfigurationError
                    .configurationWriteFailed
            }
        }
        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: url.path
            )
        } catch {
            throw CodexRuntimeConfigurationError.configurationWriteFailed
        }
    }

    private func removeRuntimeChildren(
        _ urls: [URL]
    ) throws {
        for url in urls {
            let standardized =
                url.standardizedFileURL
            guard standardized
                    .deletingLastPathComponent()
                    .standardizedFileURL
                    == rootURL,
                  standardized.path
                    .hasPrefix(rootURL.path + "/")
            else {
                throw CodexRuntimeConfigurationError
                    .unsafeStorageItem
            }
            guard fileManager.fileExists(
                atPath: standardized.path
            ) else {
                continue
            }
            let values = try standardized
                .resourceValues(
                    forKeys: [
                        .isDirectoryKey,
                        .isSymbolicLinkKey
                    ]
                )
            guard values.isDirectory == true,
                  values.isSymbolicLink != true
            else {
                throw CodexRuntimeConfigurationError
                    .unsafeStorageItem
            }
            try fileManager.removeItem(
                at: standardized
            )
        }
    }

    private func writeStrictConfiguration(to url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true
            else {
                throw CodexRuntimeConfigurationError.unsafeStorageItem
            }
        }
        let data = Data(Self.strictConfiguration.utf8)
        do {
            if (try? Data(contentsOf: url)) != data {
                try data.write(to: url, options: .atomic)
            }
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            throw CodexRuntimeConfigurationError.configurationWriteFailed
        }
    }
}

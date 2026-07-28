import Foundation
@testable import MeetingBuddyAI
import Testing

@Suite(.serialized)
struct CodexRuntimeContractTests {
    @Test
    func discoveryRequiresExactSignatureVersionAndBinaryBuild() async throws {
        let candidate = CodexRuntimeCandidate(
            url: URL(fileURLWithPath: "/synthetic/codex"),
            source: .verifiedSystemInstallation
        )
        let policy = CodexRuntimeCompatibilityPolicy(
            version: "0.146.0-alpha.3.1",
            executableSHA256: "verified-digest",
            signingIdentifier: "codex",
            signingTeamIdentifier: "2DC432GLL2"
        )
        let ready = CodexRuntimeManager(
            policy: policy,
            candidates: [candidate],
            verifier: dependencies(
                version: policy.version,
                digest: policy.executableSHA256
            )
        )
        guard case let .ready(authorization) = await ready.discover()
        else {
            Issue.record("The exact synthetic runtime was not authorized.")
            return
        }
        #expect(authorization.descriptor.version == policy.version)
        #expect(
            authorization.descriptor.source
                == .verifiedSystemInstallation
        )
        #expect(
            authorization.descriptor.executableSHA256
                == policy.executableSHA256
        )

        let wrongVersion = CodexRuntimeManager(
            policy: policy,
            candidates: [candidate],
            verifier: dependencies(
                version: "0.147.0",
                digest: policy.executableSHA256
            )
        )
        #expect(
            await wrongVersion.discover()
                == .incompatible(
                    observedVersion: "0.147.0",
                    reason: .unsupportedVersion
                )
        )

        let wrongBuild = CodexRuntimeManager(
            policy: policy,
            candidates: [candidate],
            verifier: dependencies(
                version: policy.version,
                digest: "different-digest"
            )
        )
        #expect(
            await wrongBuild.discover()
                == .incompatible(
                    observedVersion: nil,
                    reason: .untestedBinaryBuild
                )
        )

        let unsigned = CodexRuntimeManager(
            policy: policy,
            candidates: [candidate],
            verifier: dependencies(
                signatureTrusted: false,
                version: policy.version,
                digest: policy.executableSHA256
            )
        )
        #expect(await unsigned.discover() == .untrustedInstallation)

        let missing = CodexRuntimeManager(
            policy: policy,
            candidates: [candidate],
            verifier: dependencies(
                executable: false,
                version: policy.version,
                digest: policy.executableSHA256
            )
        )
        #expect(await missing.discover() == .missing)
    }

    @Test
    func binaryDigestIsVerifiedBeforeTheCandidateIsExecuted()
        async
    {
        let candidate = CodexRuntimeCandidate(
            url: URL(
                fileURLWithPath:
                    "/synthetic/codex"
            ),
            source:
                .verifiedSystemInstallation
        )
        let policy =
            CodexRuntimeCompatibilityPolicy(
                version:
                    "0.146.0-alpha.3.1",
                executableSHA256:
                    "verified-digest",
                signingIdentifier:
                    "codex",
                signingTeamIdentifier:
                    "2DC432GLL2"
            )
        let readyProbe =
            RuntimeVerificationOrderProbe(
                version: policy.version,
                digest:
                    policy.executableSHA256
            )
        let ready = CodexRuntimeManager(
            policy: policy,
            candidates: [candidate],
            verifier:
                readyProbe.dependencies()
        )
        guard case .ready =
                await ready.discover()
        else {
            Issue.record(
                "The ordered verifier did not authorize the exact build."
            )
            return
        }
        #expect(
            readyProbe.calls()
                == [
                    "executable",
                    "signature",
                    "sha256",
                    "version"
                ]
        )

        let rejectedProbe =
            RuntimeVerificationOrderProbe(
                version: policy.version,
                digest: "wrong-digest"
            )
        let rejected =
            CodexRuntimeManager(
                policy: policy,
                candidates: [candidate],
                verifier:
                    rejectedProbe
                    .dependencies()
            )
        #expect(
            await rejected.discover()
                == .incompatible(
                    observedVersion: nil,
                    reason:
                        .untestedBinaryBuild
                )
        )
        #expect(
            rejectedProbe.calls()
                == [
                    "executable",
                    "signature",
                    "sha256"
                ]
        )
    }

    @Test
    func confinementWritesStrictPrivateConfigAndDropsSecretEnvironment()
        async throws
    {
        let policy = CodexRuntimeCompatibilityPolicy(
            version: "0.146.0-alpha.3.1",
            executableSHA256: "verified-digest",
            signingIdentifier: "codex",
            signingTeamIdentifier: "2DC432GLL2"
        )
        let runtime = CodexRuntimeManager(
            policy: policy,
            candidates: [
                CodexRuntimeCandidate(
                    url: URL(fileURLWithPath: "/synthetic/codex"),
                    source: .verifiedSystemInstallation
                )
            ],
            verifier: dependencies(
                version: policy.version,
                digest: policy.executableSHA256
            )
        )
        guard case let .ready(authorization) = await runtime.discover()
        else {
            Issue.record("The synthetic runtime was not authorized.")
            return
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "blueminutes-codex-runtime-\(UUID().uuidString.lowercased())",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = try CodexRuntimeEnvironmentManager(
            rootURL: root,
            sourceEnvironment: [
                "HOME": "/Users/synthetic",
                "USER": "synthetic",
                "LOGNAME": "synthetic",
                "OPENAI_API_KEY": "must-not-cross",
                "HTTPS_PROXY": "must-not-cross",
                "SHELL": "/bin/zsh",
                "PATH": "/untrusted/path"
            ]
        )
        let configuration = try await manager.prepare(
            authorization: authorization,
            contextToolEnabled: true
        )
        #expect(configuration.arguments == [
            "app-server",
            "--strict-config",
            "--stdio"
        ])
        #expect(configuration.contextToolEnabled)
        #expect(
            Set(configuration.environment.keys)
                == [
                    "CODEX_HOME",
                    "HOME",
                    "LANG",
                    "LOGNAME",
                    "PATH",
                    "TMPDIR",
                    "USER"
                ]
        )
        #expect(configuration.environment["HOME"] == "/Users/synthetic")
        #expect(
            configuration.environment["PATH"]
                == "/usr/bin:/bin:/usr/sbin:/sbin"
        )
        #expect(configuration.environment["OPENAI_API_KEY"] == nil)
        #expect(configuration.environment["HTTPS_PROXY"] == nil)
        #expect(configuration.environment["SHELL"] == nil)
        #expect(
            try FileManager.default.contentsOfDirectory(
                at: configuration.disposableWorkingDirectoryURL,
                includingPropertiesForKeys: nil
            ).isEmpty
        )

        let configURL = configuration.codexHomeURL
            .appendingPathComponent("config.toml")
        #expect(
            try String(contentsOf: configURL, encoding: .utf8)
                == CodexRuntimeEnvironmentManager.strictConfiguration
        )
        #expect(try permissions(at: root) == 0o700)
        #expect(
            try permissions(
                at: configuration
                    .disposableWorkingDirectoryURL
            ) == 0o700
        )
        #expect(try permissions(at: configURL) == 0o600)
        #expect(
            CodexRuntimeEnvironmentManager.strictConfiguration
                .contains("forced_login_method = \"chatgpt\"")
        )
        #expect(
            CodexRuntimeEnvironmentManager.strictConfiguration
                .contains(
                    "persistence = \"none\""
                )
        )
        for denied in [
            "shell_tool = true",
            "unified_exec = true",
            "web_search = \"live\"",
            "multi_agent = true",
            "plugins = true",
            "apps = true"
        ] {
            #expect(
                !CodexRuntimeEnvironmentManager.strictConfiguration
                    .contains(denied)
            )
        }

        let workingDirectory =
            configuration.disposableWorkingDirectoryURL
        let temporaryDirectory =
            configuration.disposableTemporaryDirectoryURL
        try await manager.removeDisposableDirectories(
            for: configuration
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: workingDirectory.path
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: temporaryDirectory.path
            )
        )
        #expect(
            FileManager.default.fileExists(
                atPath: configuration.codexHomeURL.path
            )
        )
        let retainedProbe =
            configuration.codexHomeURL
            .appendingPathComponent(
                "retained-session-probe.json"
            )
        try Data("synthetic-session".utf8)
            .write(to: retainedProbe)
        try await manager
            .removePrivateRuntimeState(
                for: configuration
            )
        #expect(
            !FileManager.default.fileExists(
                atPath:
                    configuration
                    .codexHomeURL.path
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: retainedProbe.path
            )
        )
    }

    @Test
    func confinementRejectsASymbolicLinkStorageRoot() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "blueminutes-codex-symlink-\(UUID().uuidString.lowercased())",
                isDirectory: true
            )
        let target = base.appendingPathComponent(
            "target",
            isDirectory: true
        )
        let link = base.appendingPathComponent(
            "link",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: target,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: target
        )
        defer { try? FileManager.default.removeItem(at: base) }

        let policy = CodexRuntimeCompatibilityPolicy(
            version: "0.146.0-alpha.3.1",
            executableSHA256: "verified-digest",
            signingIdentifier: "codex",
            signingTeamIdentifier: "2DC432GLL2"
        )
        let runtime = CodexRuntimeManager(
            policy: policy,
            candidates: [
                CodexRuntimeCandidate(
                    url: URL(fileURLWithPath: "/synthetic/codex"),
                    source: .verifiedSystemInstallation
                )
            ],
            verifier: dependencies(
                version: policy.version,
                digest: policy.executableSHA256
            )
        )
        guard case let .ready(authorization) = await runtime.discover()
        else {
            Issue.record("The synthetic runtime was not authorized.")
            return
        }
        let manager = try CodexRuntimeEnvironmentManager(
            rootURL: link,
            sourceEnvironment: [
                "HOME": "/Users/synthetic",
                "USER": "synthetic",
                "LOGNAME": "synthetic"
            ]
        )
        await #expect(throws: CodexRuntimeConfigurationError.self) {
            _ = try await manager.prepare(
                authorization: authorization,
                contextToolEnabled: false
            )
        }
    }

    @Test
    func preparePurgesSessionBytesLeftByAnUncleanExit()
        async throws
    {
        let policy =
            CodexRuntimeCompatibilityPolicy(
                version:
                    "0.146.0-alpha.3.1",
                executableSHA256:
                    "verified-digest",
                signingIdentifier:
                    "codex",
                signingTeamIdentifier:
                    "2DC432GLL2"
            )
        let runtime = CodexRuntimeManager(
            policy: policy,
            candidates: [
                CodexRuntimeCandidate(
                    url: URL(
                        fileURLWithPath:
                            "/synthetic/codex"
                    ),
                    source:
                        .verifiedSystemInstallation
                )
            ],
            verifier: dependencies(
                version: policy.version,
                digest:
                    policy.executableSHA256
            )
        )
        guard case let .ready(authorization) =
                await runtime.discover()
        else {
            Issue.record(
                "The synthetic runtime was not authorized."
            )
            return
        }
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "blueminutes-codex-stale-\(UUID().uuidString.lowercased())",
                isDirectory: true
            )
        defer {
            try? FileManager.default
                .removeItem(at: root)
        }
        let manager =
            try CodexRuntimeEnvironmentManager(
                rootURL: root,
                sourceEnvironment: [
                    "HOME":
                        "/Users/synthetic",
                    "USER": "synthetic",
                    "LOGNAME": "synthetic"
                ]
            )
        let first = try await manager.prepare(
            authorization: authorization,
            contextToolEnabled: true
        )
        let staleSession = first.codexHomeURL
            .appendingPathComponent(
                "sessions/stale.json"
            )
        try FileManager.default
            .createDirectory(
                at:
                    staleSession
                    .deletingLastPathComponent(),
                withIntermediateDirectories:
                    true
            )
        try Data("private meeting bytes".utf8)
            .write(to: staleSession)

        let second = try await manager.prepare(
            authorization: authorization,
            contextToolEnabled: true
        )

        #expect(
            !FileManager.default.fileExists(
                atPath: staleSession.path
            )
        )
        #expect(
            try FileManager.default
                .contentsOfDirectory(
                    at:
                        second
                        .codexHomeURL,
                    includingPropertiesForKeys:
                        nil
                )
                .map(\.lastPathComponent)
                == ["config.toml"]
        )
        try await manager
            .removePrivateRuntimeState(
                for: second
            )
    }

    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment[
                "MEETINGBUDDY_RUN_LIVE_CODEX_RUNTIME"
            ] == "1",
            "Live official Codex runtime verification is opt-in."
        )
    )
    func installedOfficialRuntimeMatchesThePinnedBuild() async {
        let result = await CodexRuntimeManager().discover()
        guard case let .ready(authorization) = result else {
            Issue.record(
                "The installed official Codex runtime did not match the pinned build."
            )
            return
        }
        #expect(
            authorization.descriptor.version
                == CodexRuntimeCompatibilityPolicy.verified.version
        )
        #expect(
            authorization.descriptor.executableSHA256
                == CodexRuntimeCompatibilityPolicy
                .verified.executableSHA256
        )
    }
}

private func dependencies(
    executable: Bool = true,
    signatureTrusted: Bool = true,
    version: String?,
    digest: String?
) -> CodexRuntimeVerificationDependencies {
    CodexRuntimeVerificationDependencies(
        isExecutable: { _ in executable },
        hasTrustedSignature: { _, identifier, teamIdentifier in
            signatureTrusted
                && identifier == "codex"
                && teamIdentifier == "2DC432GLL2"
        },
        version: { _ in version },
        sha256: { _ in digest }
    )
}

private func permissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(
        atPath: url.path
    )
    return try #require(
        attributes[.posixPermissions] as? NSNumber
    ).intValue
}

private final class RuntimeVerificationOrderProbe:
    @unchecked Sendable
{
    private let lock = NSLock()
    private let observedVersion: String?
    private let observedDigest: String?
    private var observedCalls: [String] = []

    init(
        version: String?,
        digest: String?
    ) {
        observedVersion = version
        observedDigest = digest
    }

    func dependencies()
        -> CodexRuntimeVerificationDependencies
    {
        CodexRuntimeVerificationDependencies(
            isExecutable: { [self] _ in
                record("executable")
                return true
            },
            hasTrustedSignature: {
                [self] _,
                identifier,
                teamIdentifier in
                record("signature")
                return identifier == "codex"
                    && teamIdentifier
                        == "2DC432GLL2"
            },
            version: { [self] _ in
                record("version")
                return observedVersion
            },
            sha256: { [self] _ in
                record("sha256")
                return observedDigest
            }
        )
    }

    func calls() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return observedCalls
    }

    private func record(_ call: String) {
        lock.lock()
        observedCalls.append(call)
        lock.unlock()
    }
}

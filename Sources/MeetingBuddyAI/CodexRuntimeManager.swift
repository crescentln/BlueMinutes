import CryptoKit
import Darwin
import Foundation
import Security

public enum CodexRuntimeSource: String, Hashable, Sendable {
    case chatGPTApplication = "chatgpt_application"
    case verifiedSystemInstallation = "verified_system_installation"

    public var displayName: String {
        switch self {
        case .chatGPTApplication:
            "ChatGPT application installation"
        case .verifiedSystemInstallation:
            "Verified system installation"
        }
    }
}

public enum CodexRuntimeIncompatibility: String, Hashable, Sendable {
    case unsupportedVersion = "unsupported_version"
    case untestedBinaryBuild = "untested_binary_build"
}

public struct CodexRuntimeDescriptor: Hashable, Sendable {
    public let version: String
    public let source: CodexRuntimeSource
    public let executableSHA256: String

    let executableURL: URL
}

/// Required to launch the agentic runtime. Only successful signature, version,
/// and exact-build verification can construct this value.
public struct CodexRuntimeLaunchAuthorization: Hashable, Sendable {
    public let descriptor: CodexRuntimeDescriptor

    fileprivate init(descriptor: CodexRuntimeDescriptor) {
        self.descriptor = descriptor
    }
}

public enum CodexRuntimeDiscovery: Hashable, Sendable {
    case ready(CodexRuntimeLaunchAuthorization)
    case missing
    case untrustedInstallation
    case incompatible(
        observedVersion: String?,
        reason: CodexRuntimeIncompatibility
    )
}

public struct CodexRuntimeCompatibilityPolicy: Hashable, Sendable {
    public static let verified = CodexRuntimeCompatibilityPolicy(
        version: "0.146.0-alpha.3.1",
        executableSHA256:
            "6d8be49e49751554df16572369e636cbe02c84b208cad3dc35528c846eeca223",
        signingIdentifier: "codex",
        signingTeamIdentifier: "2DC432GLL2"
    )

    public let version: String
    public let executableSHA256: String
    public let signingIdentifier: String
    public let signingTeamIdentifier: String
}

public struct CodexRuntimeManager: Sendable {
    private let policy: CodexRuntimeCompatibilityPolicy
    private let candidates: [CodexRuntimeCandidate]
    private let verifier: CodexRuntimeVerificationDependencies

    public init(
        policy: CodexRuntimeCompatibilityPolicy = .verified
    ) {
        self.init(
            policy: policy,
            candidates: [
                CodexRuntimeCandidate(
                    url: URL(
                        fileURLWithPath:
                            "/Applications/ChatGPT.app/Contents/Resources/codex"
                    ),
                    source: .chatGPTApplication
                ),
                CodexRuntimeCandidate(
                    url: URL(
                        fileURLWithPath: "/opt/homebrew/bin/codex"
                    ),
                    source: .verifiedSystemInstallation
                )
            ],
            verifier: .live
        )
    }

    init(
        policy: CodexRuntimeCompatibilityPolicy,
        candidates: [CodexRuntimeCandidate],
        verifier: CodexRuntimeVerificationDependencies
    ) {
        self.policy = policy
        self.candidates = candidates
        self.verifier = verifier
    }

    public func discover() async -> CodexRuntimeDiscovery {
        await Task.detached(priority: .utility) {
            discoverSynchronously()
        }.value
    }

    private func discoverSynchronously() -> CodexRuntimeDiscovery {
        var sawCandidate = false
        var sawUntrustedCandidate = false
        var incompatible:
            (observedVersion: String?, reason: CodexRuntimeIncompatibility)?
        var visited = Set<String>()

        for candidate in candidates {
            guard verifier.isExecutable(candidate.url) else { continue }
            sawCandidate = true
            let resolved = candidate.url.resolvingSymlinksInPath()
                .standardizedFileURL
            guard resolved.isFileURL,
                  resolved.path.hasPrefix("/")
            else {
                sawUntrustedCandidate = true
                continue
            }
            guard visited.insert(resolved.path).inserted else { continue }
            guard verifier.hasTrustedSignature(
                resolved,
                policy.signingIdentifier,
                policy.signingTeamIdentifier
            ) else {
                sawUntrustedCandidate = true
                continue
            }
            guard verifier.sha256(resolved) == policy.executableSHA256 else {
                incompatible = (nil, .untestedBinaryBuild)
                continue
            }
            guard let version = verifier.version(resolved),
                  CodexSemanticVersion(version) != nil
            else {
                incompatible = (nil, .unsupportedVersion)
                continue
            }
            guard version == policy.version else {
                incompatible = (version, .unsupportedVersion)
                continue
            }

            let source: CodexRuntimeSource =
                resolved.path
                    == "/Applications/ChatGPT.app/Contents/Resources/codex"
                ? .chatGPTApplication
                : candidate.source
            return .ready(
                CodexRuntimeLaunchAuthorization(
                    descriptor: CodexRuntimeDescriptor(
                        version: version,
                        source: source,
                        executableSHA256: policy.executableSHA256,
                        executableURL: resolved
                    )
                )
            )
        }

        if let incompatible {
            return .incompatible(
                observedVersion: incompatible.observedVersion,
                reason: incompatible.reason
            )
        }
        if sawUntrustedCandidate {
            return .untrustedInstallation
        }
        return sawCandidate ? .untrustedInstallation : .missing
    }
}

struct CodexRuntimeCandidate: Hashable, Sendable {
    let url: URL
    let source: CodexRuntimeSource
}

struct CodexRuntimeVerificationDependencies: Sendable {
    let isExecutable: @Sendable (URL) -> Bool
    let hasTrustedSignature:
        @Sendable (URL, String, String) -> Bool
    let version: @Sendable (URL) -> String?
    let sha256: @Sendable (URL) -> String?

    static let live = CodexRuntimeVerificationDependencies(
        isExecutable: { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(
                atPath: url.path,
                isDirectory: &isDirectory
            )
                && !isDirectory.boolValue
                && FileManager.default.isExecutableFile(atPath: url.path)
        },
        hasTrustedSignature: {
            url,
            expectedIdentifier,
            expectedTeamIdentifier in
            var staticCode: SecStaticCode?
            guard SecStaticCodeCreateWithPath(
                url as CFURL,
                SecCSFlags(),
                &staticCode
            ) == errSecSuccess,
                let staticCode,
                SecStaticCodeCheckValidity(
                    staticCode,
                    SecCSFlags(
                        rawValue: UInt32(
                            kSecCSCheckAllArchitectures
                                | kSecCSStrictValidate
                        )
                    ),
                    nil
                ) == errSecSuccess
            else {
                return false
            }

            var signingInformation: CFDictionary?
            guard SecCodeCopySigningInformation(
                staticCode,
                SecCSFlags(
                    rawValue: UInt32(kSecCSSigningInformation)
                ),
                &signingInformation
            ) == errSecSuccess,
                let values = signingInformation as? [CFString: Any],
                values[kSecCodeInfoIdentifier] as? String
                    == expectedIdentifier,
                values[kSecCodeInfoTeamIdentifier] as? String
                    == expectedTeamIdentifier
            else {
                return false
            }
            return true
        },
        version: { url in
            readCodexVersion(at: url)
        },
        sha256: { url in
            sha256OfFile(at: url)
        }
    )
}

private struct CodexSemanticVersion: Hashable, Sendable {
    init?(_ value: String) {
        let withoutBuild = value.split(
            separator: "+",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )[0]
        let pieces = withoutBuild.split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let core = pieces[0].split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard core.count == 3,
              core.allSatisfy({
                  !$0.isEmpty
                      && $0.allSatisfy(\.isNumber)
                      && ($0 == "0" || $0.first != "0")
              }),
              pieces.count == 1
                  || (
                      pieces[1].isEmpty == false
                          && pieces[1].allSatisfy {
                              $0.isASCII
                                  && (
                                      $0.isLetter
                                          || $0.isNumber
                                          || $0 == "."
                                          || $0 == "-"
                                  )
                          }
                  )
        else {
            return nil
        }
    }
}

private func readCodexVersion(at executableURL: URL) -> String? {
    let process = Process()
    let standardOutput = Pipe()
    let completed = DispatchSemaphore(value: 0)
    process.executableURL = executableURL
    process.arguments = ["--version"]
    process.environment = [
        "LANG": "en_US.UTF-8",
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
    ]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = standardOutput
    process.standardError = FileHandle.nullDevice
    process.terminationHandler = { _ in completed.signal() }

    do {
        try process.run()
    } catch {
        return nil
    }
    if completed.wait(timeout: .now() + 3) == .timedOut {
        process.terminate()
        if completed.wait(timeout: .now() + 1) == .timedOut {
            Darwin.kill(process.processIdentifier, SIGKILL)
            _ = completed.wait(timeout: .now() + 1)
        }
        return nil
    }
    guard process.terminationStatus == 0 else { return nil }
    let data = standardOutput.fileHandleForReading.readDataToEndOfFile()
    guard data.count <= 4_096,
          let output = String(data: data, encoding: .utf8)
    else {
        return nil
    }
    let trimmed = output.trimmingCharacters(
        in: .whitespacesAndNewlines
    )
    let prefix = "codex-cli "
    guard trimmed.hasPrefix(prefix) else { return nil }
    let version = String(trimmed.dropFirst(prefix.count))
    guard version.utf8.count <= 128,
          !version.unicodeScalars.contains(
              where: CharacterSet.controlCharacters.contains
          )
    else {
        return nil
    }
    return version
}

private func sha256OfFile(at url: URL) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else {
        return nil
    }
    defer { try? handle.close() }
    var hasher = SHA256()
    do {
        while let data = try handle.read(upToCount: 1_048_576),
              !data.isEmpty
        {
            hasher.update(data: data)
        }
    } catch {
        return nil
    }
    return hasher.finalize().map {
        String(format: "%02x", $0)
    }.joined()
}

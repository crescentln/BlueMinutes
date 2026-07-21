import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

public enum AutomationCLIExitCode: Int32, Sendable {
    case success = 0
    case usage = 64
    case invalidData = 65
    case notFound = 66
    case unavailable = 69
    case internalFailure = 70
    case settingsConflict = 73
    case persistenceFailure = 74
    case permissionDenied = 77
    case configuration = 78
}

public struct AutomationCLIOutput: Sendable, Equatable {
    public let standardOutput: Data?
    public let standardError: Data?
    public let exitCode: AutomationCLIExitCode

    public init(
        standardOutput: Data?,
        standardError: Data?,
        exitCode: AutomationCLIExitCode
    ) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exitCode = exitCode
    }
}

public enum AutomationCLIWorkspacePath {
    /// Accepts one exact, existing-or-resolvable absolute local path. Relative,
    /// root, traversal, control-character, repeated-separator, and symlinked
    /// paths are rejected before the workspace service sees them.
    public static func validatedURL(_ path: String) -> URL? {
        guard path.hasPrefix("/"),
              path != "/",
              path.utf8.count <= 4_096,
              !path.hasPrefix("~"),
              !path.contains("\\"),
              !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            return nil
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.first?.isEmpty == true,
              components.dropFirst().allSatisfy({
                  !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255
              })
        else {
            return nil
        }
        let standardized = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        guard standardized.path == path,
              standardized.resolvingSymlinksInPath().standardizedFileURL.path
                == standardized.path
        else {
            return nil
        }
        return standardized
    }
}

/// Strict argv-to-command transport. It has no workspace, policy, database,
/// filesystem, or permission mutation API of its own.
public struct AutomationCLIAdapter: Sendable {
    public static let version = "meetingbuddy-cli-v1"
    public static let helpText = """
    meetingbuddy-cli --workspace <absolute-path> [--command-id <uuid>] [--replay-nonce <uuid>] <command>

    Commands:
      catalog
      status workspace
      status meeting-policy --meeting-id <uuid>
      status storage [--maximum-entries <1...100000>]
      settings get
      settings describe
      settings patch --expected-version <n> --status-list-limit <1...200>
      settings rollback --target-command-id <uuid> --expected-version <n>
      activity list [--limit <1...200>]
      diagnostics run [--maximum-entries <1...100000>]
    """

    private let executor: any AutomationCommandExecuting
    private let clock: @Sendable () throws -> UTCInstant
    private let makeUUID: @Sendable () -> UUID

    public init(
        executor: any AutomationCommandExecuting,
        clock: @escaping @Sendable () throws -> UTCInstant = {
            try UTCInstant(
                millisecondsSinceUnixEpoch: Int64(
                    (Date().timeIntervalSince1970 * 1_000).rounded(.down)
                )
            )
        },
        makeUUID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.executor = executor
        self.clock = clock
        self.makeUUID = makeUUID
    }

    public func run(arguments: [String]) async -> AutomationCLIOutput {
        do {
            let invocation = try parse(arguments)
            let request = AutomationCommandRequest(
                commandID: invocation.commandID,
                replayNonce: invocation.replayNonce,
                command: invocation.command,
                issuedAt: try clock()
            )
            let execution = try await executor.execute(request)
            return AutomationCLIOutput(
                standardOutput: try Self.line(CanonicalJSON.encode(execution)),
                standardError: nil,
                exitCode: .success
            )
        } catch {
            return Self.errorOutput(for: error)
        }
    }

    public static func errorOutput(for error: Error) -> AutomationCLIOutput {
        let mapped = map(error)
        let envelope = AutomationCLIErrorEnvelope(
            schemaVersion: 1,
            error: AutomationCLIErrorBody(code: mapped.code, message: mapped.message)
        )
        let data = (try? line(CanonicalJSON.encode(envelope)))
            ?? Data("{\"error\":{\"code\":\"internal_failure\",\"message\":\"The command failed safely.\"},\"schema_version\":1}\n".utf8)
        return AutomationCLIOutput(
            standardOutput: nil,
            standardError: data,
            exitCode: mapped.exitCode
        )
    }

    private func parse(_ arguments: [String]) throws -> ParsedInvocation {
        guard !arguments.isEmpty,
              arguments.count <= 32,
              arguments.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 4_096 }),
              arguments.allSatisfy({
                  !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
              })
        else {
            throw AutomationCLIParseError.usage
        }
        let forbiddenAuthorityFlags: Set<String> = [
            "--allow-recursion", "--confirm", "--permission", "--role"
        ]
        guard forbiddenAuthorityFlags.isDisjoint(with: arguments) else {
            throw AutomationContractError.unauthorized(
                "caller_authority_is_not_command_input"
            )
        }

        var cursor = 0
        var commandID: AutomationCommandID?
        var replayNonce: AutomationReplayNonce?
        while cursor < arguments.count, arguments[cursor].hasPrefix("--") {
            let option = arguments[cursor]
            guard option == "--command-id" || option == "--replay-nonce",
                  cursor + 1 < arguments.count
            else {
                break
            }
            let value = arguments[cursor + 1]
            if option == "--command-id" {
                guard commandID == nil else { throw AutomationCLIParseError.usage }
                commandID = try AutomationCommandID(validating: value)
            } else {
                guard replayNonce == nil else { throw AutomationCLIParseError.usage }
                replayNonce = try AutomationReplayNonce(validating: value)
            }
            cursor += 2
        }
        guard cursor < arguments.count else { throw AutomationCLIParseError.usage }

        let commandArguments = Array(arguments[cursor...])
        let command = try parseCommand(commandArguments)
        return ParsedInvocation(
            commandID: commandID ?? AutomationCommandID(makeUUID()),
            replayNonce: replayNonce ?? AutomationReplayNonce(makeUUID()),
            command: command
        )
    }

    private func parseCommand(_ arguments: [String]) throws -> AutomationCommand {
        guard let root = arguments.first else { throw AutomationCLIParseError.usage }
        if Self.unavailableRoots.contains(root) {
            throw AutomationContractError.commandUnavailable(
                "capability_unavailable_task_009a"
            )
        }
        switch root {
        case "catalog":
            guard arguments.count == 1 else { throw AutomationCLIParseError.usage }
            return .getCommandCatalog
        case "status":
            return try parseStatus(Array(arguments.dropFirst()))
        case "settings":
            return try parseSettings(Array(arguments.dropFirst()))
        case "activity":
            return try parseActivity(Array(arguments.dropFirst()))
        case "diagnostics":
            return try parseDiagnostics(Array(arguments.dropFirst()))
        default:
            throw AutomationCLIParseError.usage
        }
    }

    private func parseStatus(_ arguments: [String]) throws -> AutomationCommand {
        guard let kind = arguments.first else { throw AutomationCLIParseError.usage }
        switch kind {
        case "workspace":
            guard arguments.count == 1 else { throw AutomationCLIParseError.usage }
            return .getWorkspaceStatus
        case "meeting-policy":
            let options = try parseOptions(
                Array(arguments.dropFirst()),
                allowed: ["--meeting-id"]
            )
            guard let value = options["--meeting-id"], options.count == 1 else {
                throw AutomationCLIParseError.usage
            }
            return .getMeetingPolicyStatus(
                AutomationMeetingPolicyRequest(
                    meetingID: try MeetingID(validating: value)
                )
            )
        case "storage":
            let options = try parseOptions(
                Array(arguments.dropFirst()),
                allowed: ["--maximum-entries"]
            )
            let maximum = try uint32(
                options["--maximum-entries"] ?? "10000",
                range: 1...100_000
            )
            return .getStorageReport(
                try AutomationStorageReportRequest(maximumEntries: maximum)
            )
        default:
            throw AutomationCLIParseError.usage
        }
    }

    private func parseSettings(_ arguments: [String]) throws -> AutomationCommand {
        guard let action = arguments.first else { throw AutomationCLIParseError.usage }
        switch action {
        case "get":
            guard arguments.count == 1 else { throw AutomationCLIParseError.usage }
            return .getSettings
        case "describe":
            guard arguments.count == 1 else { throw AutomationCLIParseError.usage }
            return .describeSettings
        case "patch":
            let options = try parseOptions(
                Array(arguments.dropFirst()),
                allowed: ["--expected-version", "--status-list-limit"]
            )
            guard let version = options["--expected-version"],
                  let limit = options["--status-list-limit"],
                  options.count == 2
            else {
                throw AutomationCLIParseError.usage
            }
            return .updateSettings(
                try AutomationSettingsPatch(
                    expectedVersion: uint64(version),
                    statusListLimit: uint16(limit, range: 1...200)
                )
            )
        case "rollback":
            let options = try parseOptions(
                Array(arguments.dropFirst()),
                allowed: ["--target-command-id", "--expected-version"]
            )
            guard let target = options["--target-command-id"],
                  let version = options["--expected-version"],
                  options.count == 2
            else {
                throw AutomationCLIParseError.usage
            }
            return .rollbackSettings(
                AutomationSettingsRollbackRequest(
                    targetCommandID: try AutomationCommandID(validating: target),
                    expectedVersion: try uint64(version)
                )
            )
        default:
            throw AutomationCLIParseError.usage
        }
    }

    private func parseActivity(_ arguments: [String]) throws -> AutomationCommand {
        guard arguments.first == "list" else { throw AutomationCLIParseError.usage }
        let options = try parseOptions(
            Array(arguments.dropFirst()),
            allowed: ["--limit"]
        )
        let limit = try options["--limit"].map { try uint16($0, range: 1...200) }
        return .listActivity(try AutomationActivityRequest(limit: limit))
    }

    private func parseDiagnostics(_ arguments: [String]) throws -> AutomationCommand {
        guard arguments.first == "run" else { throw AutomationCLIParseError.usage }
        let options = try parseOptions(
            Array(arguments.dropFirst()),
            allowed: ["--maximum-entries"]
        )
        let maximum = try uint32(
            options["--maximum-entries"] ?? "10000",
            range: 1...100_000
        )
        return .runWorkspaceDiagnostics(
            try AutomationDiagnosticsRequest(maximumEntries: maximum)
        )
    }

    private func parseOptions(
        _ arguments: [String],
        allowed: Set<String>
    ) throws -> [String: String] {
        guard arguments.count.isMultiple(of: 2) else {
            throw AutomationCLIParseError.usage
        }
        var result: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            let value = arguments[index + 1]
            guard allowed.contains(key),
                  result[key] == nil,
                  !value.hasPrefix("--")
            else {
                throw AutomationCLIParseError.usage
            }
            result[key] = value
            index += 2
        }
        return result
    }

    private func uint16(
        _ value: String,
        range: ClosedRange<UInt16>
    ) throws -> UInt16 {
        guard let parsed = UInt16(value), range.contains(parsed) else {
            throw AutomationContractError.invalidRequest("A numeric bound is invalid.")
        }
        return parsed
    }

    private func uint32(
        _ value: String,
        range: ClosedRange<UInt32>
    ) throws -> UInt32 {
        guard let parsed = UInt32(value), range.contains(parsed) else {
            throw AutomationContractError.invalidRequest("A numeric bound is invalid.")
        }
        return parsed
    }

    private func uint64(_ value: String) throws -> UInt64 {
        guard let parsed = UInt64(value) else {
            throw AutomationContractError.invalidRequest("A version is invalid.")
        }
        return parsed
    }

    private static func line(_ data: Data) -> Data {
        var output = data
        output.append(0x0a)
        return output
    }

    private static func map(
        _ error: Error
    ) -> (exitCode: AutomationCLIExitCode, code: String, message: String) {
        if error is AutomationCLIParseError {
            return (.usage, "usage_error", "The command syntax is invalid. Use --help.")
        }
        guard let error = error as? AutomationContractError else {
            return (.internalFailure, "internal_failure", "The command failed safely.")
        }
        switch error {
        case .invalidRequest:
            return (.invalidData, "invalid_request", "The command input is invalid.")
        case .invalidCaller:
            return (.permissionDenied, "invalid_caller", "The caller context was rejected.")
        case .unauthorized:
            return (.permissionDenied, "permission_denied", "The caller is not authorized.")
        case .policyDenied:
            return (.permissionDenied, "policy_denied", "Current policy denied the command.")
        case .replayDetected:
            return (.permissionDenied, "replay_detected", "The command replay was rejected.")
        case .settingsConflict:
            return (.settingsConflict, "settings_conflict", "The settings version changed.")
        case .commandUnavailable:
            return (.unavailable, "command_unavailable", "That capability is unavailable.")
        case .persistenceFailure:
            return (.persistenceFailure, "persistence_failure", "The local operation failed safely.")
        }
    }

    private static let unavailableRoots: Set<String> = [
        "access-policy", "credential", "credentials", "database", "delete",
        "export", "filesystem", "http", "job", "mcp", "model", "network",
        "provider", "purge", "record", "recording", "serve", "sql"
    ]
}

private struct ParsedInvocation: Sendable {
    let commandID: AutomationCommandID
    let replayNonce: AutomationReplayNonce
    let command: AutomationCommand
}

private enum AutomationCLIParseError: Error, Sendable {
    case usage
}

private struct AutomationCLIErrorEnvelope: Codable, Sendable {
    let schemaVersion: UInt16
    let error: AutomationCLIErrorBody

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case error
    }
}

private struct AutomationCLIErrorBody: Codable, Sendable {
    let code: String
    let message: String
}

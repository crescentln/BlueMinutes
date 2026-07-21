import Darwin
import Foundation
import MeetingBuddyApplication
import MeetingBuddyAutomation
import MeetingBuddyDomain
import MeetingBuddyPersistence

@main
enum MeetingBuddyCLIEntry {
    static func main() async {
        let output = await run()
        if let standardOutput = output.standardOutput {
            try? FileHandle.standardOutput.write(contentsOf: standardOutput)
        }
        if let standardError = output.standardError {
            try? FileHandle.standardError.write(contentsOf: standardError)
        }
        Darwin.exit(output.exitCode.rawValue)
    }

    private static func run() async -> AutomationCLIOutput {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--help"] || arguments == ["-h"] {
            return AutomationCLIOutput(
                standardOutput: Data((AutomationCLIAdapter.helpText + "\n").utf8),
                standardError: nil,
                exitCode: .success
            )
        }
        guard arguments.count >= 3,
              arguments[0] == "--workspace",
              let workspaceURL = AutomationCLIWorkspacePath.validatedURL(arguments[1])
        else {
            return usageError()
        }

        do {
            let workspace = try LocalWorkspaceService().openWorkspace(at: workspaceURL)
            let store = try SQLitePersistenceStore(workspace: workspace)
            defer { try? store.close() }
            let repository = SQLiteAutomationRepository(store: store)
            let caller = try AutomationCallerContext(
                workspaceID: workspace.manifest.workspaceID,
                actorID: AutomationActorID("local_cli"),
                origin: .cli,
                maximumPermission: .operational,
                adapterVersion: AutomationCLIAdapter.version
            )
            let service = AutomationCommandService(
                repository: repository,
                temporaryStorage: LocalTaskTemporaryStorage(workspace: workspace),
                caller: caller
            )
            return await AutomationCLIAdapter(executor: service).run(
                arguments: Array(arguments.dropFirst(2))
            )
        } catch {
            return AutomationCLIAdapter.errorOutput(
                for: AutomationContractError.persistenceFailure(
                    "workspace_open_failed"
                )
            )
        }
    }

    private static func usageError() -> AutomationCLIOutput {
        AutomationCLIOutput(
            standardOutput: nil,
            standardError: Data(
                "{\"error\":{\"code\":\"usage_error\",\"message\":\"The command syntax is invalid. Use --help.\"},\"schema_version\":1}\n".utf8
            ),
            exitCode: .usage
        )
    }
}

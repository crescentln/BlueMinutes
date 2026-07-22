import Darwin
import Foundation
import MeetingBuddyApplication
import MeetingBuddyAutomation
import MeetingBuddyDomain
import MeetingBuddyPersistence

@main
enum MeetingBuddyMCPEntry {
    private static let approvalFlag = "--approve-read-tools-with-local-audit"
    private static let helpText = """
    meetingbuddy-mcp --workspace <absolute-path> --approve-read-tools-with-local-audit

    Runs a local MCP 2025-11-25 stdio server with read-authority BlueMinutes tools.
    Tool calls write bounded local audit metadata. Opening an accepted schema-v8
    workspace first creates its verified rollback backup and migrates it to v9.
    Configuration and launch of this exact command approve those local effects.
    """

    static func main() async {
        Darwin.exit(await run())
    }

    private static func run() async -> Int32 {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--help"] || arguments == ["-h"] {
            writeStandardError(helpText + "\n")
            return 0
        }
        guard arguments.count == 3,
              arguments[0] == "--workspace",
              arguments[2] == approvalFlag,
              let workspaceURL = AutomationCLIWorkspacePath.validatedURL(arguments[1])
        else {
            writeStandardError("meetingbuddy-mcp: invalid local read-tools launch configuration\n")
            return 64
        }

        do {
            let workspace = try LocalWorkspaceService().openWorkspace(at: workspaceURL)
            let store = try SQLitePersistenceStore(workspace: workspace)
            defer { try? store.close() }
            let caller = try AutomationCallerContext(
                workspaceID: workspace.manifest.workspaceID,
                actorID: AutomationActorID("local_mcp"),
                origin: .mcp,
                maximumPermission: .read,
                adapterVersion: AutomationMCPProtocol.adapterVersion,
                ancestorBoundaries: [.externalAgent]
            )
            let service = AutomationCommandService(
                repository: SQLiteAutomationRepository(store: store),
                temporaryStorage: LocalTaskTemporaryStorage(workspace: workspace),
                caller: caller
            )
            let adapter = AutomationMCPAdapter(executor: service)
            return await serve(adapter)
        } catch {
            writeStandardError("meetingbuddy-mcp: local workspace initialization failed safely\n")
            return 74
        }
    }

    private static func serve(_ adapter: AutomationMCPAdapter) async -> Int32 {
        var framer = AutomationMCPLineFramer()
        do {
            while let chunk = try FileHandle.standardInput.read(upToCount: 8_192),
                  !chunk.isEmpty
            {
                for message in try framer.append(chunk) {
                    if let response = await adapter.receive(message) {
                        var line = response
                        line.append(0x0a)
                        try FileHandle.standardOutput.write(contentsOf: line)
                    }
                }
            }
            try framer.validateEndOfFile()
            return 0
        } catch {
            writeStandardError("meetingbuddy-mcp: stdio transport closed safely\n")
            return 65
        }
    }

    private static func writeStandardError(_ message: String) {
        try? FileHandle.standardError.write(contentsOf: Data(message.utf8))
    }
}

import Foundation
import GRDB
import MeetingBuddyApplication
import MeetingBuddyAutomation
import MeetingBuddyDomain
@testable import MeetingBuddyPersistence
import Testing

@Suite(.serialized)
struct AutomationCommandIntegrationTests {
    @Test
    func catalogIsNarrowAndCLIRejectsAuthorityAndSensitiveCapabilities() async throws {
        let catalog = AutomationCommandCatalog()
        #expect(catalog.commands.map(\.name) == AutomationCommandName.allCases)
        #expect(catalog.commands.allSatisfy { $0.confirmation == .none })
        #expect(
            Set(catalog.unavailableCapabilities.map(\.capability))
                == Set(AutomationUnavailableCapability.allCases.filter { $0 != .mcp })
        )
        let confirmationRequired: Set<AutomationUnavailableCapability> = [
            .export,
            .recording,
            .destructiveFilesystem,
            .credentials,
            .accessPolicyMutation,
            .remoteNetworkControl
        ]
        #expect(catalog.unavailableCapabilities.allSatisfy { rule in
            rule.futureConfirmationRequirement
                == (confirmationRequired.contains(rule.capability)
                    ? .trustedApplicationOneTime
                    : .none)
        })

        let executor = CountingExecutor()
        let adapter = AutomationCLIAdapter(
            executor: executor,
            clock: { TestAutomationFixture.timestamp }
        )
        for command in ["export", "recording", "provider", "delete", "mcp", "http"] {
            let unavailable = await adapter.run(arguments: [command])
            #expect(unavailable.exitCode == .unavailable)
            #expect(unavailable.standardOutput == nil)
        }

        for flag in ["--permission", "--role", "--confirm", "--allow-recursion"] {
            let authority = await adapter.run(
                arguments: [flag, "forged", "catalog"]
            )
            #expect(authority.exitCode == .permissionDenied)
            #expect(authority.standardOutput == nil)
        }

        let malformed = await adapter.run(
            arguments: [
                "settings", "patch", "--expected-version", "0",
                "--status-list-limit", "0"
            ]
        )
        #expect(malformed.exitCode == .invalidData)
        #expect(await executor.executionCount == 0)
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(
                AutomationSettingsPatch.self,
                from: Data(
                    "{\"expected_version\":0,\"status_list_limit\":0}".utf8
                )
            )
        }

        let success = await adapter.run(arguments: ["catalog"])
        #expect(success.exitCode == .success)
        #expect(success.standardError == nil)
        #expect(await executor.executionCount == 1)

        for path in ["relative", "/", "/tmp/../escape", "/tmp//duplicate"] {
            #expect(AutomationCLIWorkspacePath.validatedURL(path) == nil)
        }
        let pathRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingBuddyCLIPath-(UUID().uuidString)")
        let real = pathRoot.appendingPathComponent("real", isDirectory: true)
        let link = pathRoot.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? FileManager.default.removeItem(at: pathRoot) }
        #expect(AutomationCLIWorkspacePath.validatedURL(real.path) == real.standardizedFileURL)
        #expect(AutomationCLIWorkspacePath.validatedURL(link.path) == nil)
    }

    @Test
    func permissionAndRecursionDenialsAreAuditedWithoutChangingSettings() async throws {
        let fixture = try TestAutomationFixture()
        defer { fixture.remove() }

        let readOnly = try fixture.service(permission: .read)
        let updateID = AutomationCommandID(UUID())
        let update = AutomationCommandRequest(
            commandID: updateID,
            replayNonce: AutomationReplayNonce(UUID()),
            command: .updateSettings(
                try AutomationSettingsPatch(expectedVersion: 0, statusListLimit: 25)
            ),
            issuedAt: Self.timestamp
        )
        do {
            _ = try await readOnly.execute(update)
            Issue.record("A read-only caller unexpectedly changed settings.")
        } catch let error as AutomationContractError {
            #expect(error == .unauthorized("permission_denied"))
        }

        let root = AutomationCommandID(UUID())
        let parent = AutomationCommandID(UUID())
        let recursive = try fixture.service(
            permission: .operational,
            rootCommandID: root,
            parentCommandID: parent,
            hopCount: 1
        )
        let recursiveID = AutomationCommandID(UUID())
        do {
            _ = try await recursive.execute(
                AutomationCommandRequest(
                    commandID: recursiveID,
                    replayNonce: AutomationReplayNonce(UUID()),
                    command: .getCommandCatalog,
                    issuedAt: Self.timestamp
                )
            )
            Issue.record("A recursive command unexpectedly executed.")
        } catch let error as AutomationContractError {
            #expect(error == .policyDenied("recursive_or_provider_call_denied"))
        }

        let operationalID = AutomationCommandID(UUID())
        do {
            _ = try await readOnly.execute(
                AutomationCommandRequest(
                    commandID: operationalID,
                    replayNonce: AutomationReplayNonce(UUID()),
                    command: .runWorkspaceDiagnostics(
                        try AutomationDiagnosticsRequest(maximumEntries: 100)
                    ),
                    issuedAt: Self.timestamp
                )
            )
            Issue.record("A read-only caller unexpectedly ran diagnostics.")
        } catch let error as AutomationContractError {
            #expect(error == .unauthorized("permission_denied"))
        }

        #expect(try fixture.repository.currentAutomationSettings().version == 0)
        let trails = try fixture.repository.automationActivity(
            limit: 10,
            excludingCommandID: nil
        )
        #expect(trails.count == 3)
        #expect(trails.allSatisfy { $0.record.decision == .denied })
        #expect(trails.allSatisfy { $0.resultEvents.first?.outcome == .rejected })
        #expect(trails.contains { $0.record.commandID == updateID })
        #expect(trails.contains { $0.record.commandID == recursiveID })
        #expect(trails.contains { $0.record.commandID == operationalID })
    }

    @Test
    func settingsCASRollbackReplayAndAuditIntegrityAreEnforced() async throws {
        let fixture = try TestAutomationFixture()
        defer { fixture.remove() }
        let service = try fixture.service(permission: .operational)

        let updateID = AutomationCommandID(UUID())
        let updated = try await service.execute(
            AutomationCommandRequest(
                commandID: updateID,
                replayNonce: AutomationReplayNonce(UUID()),
                command: .updateSettings(
                    try AutomationSettingsPatch(expectedVersion: 0, statusListLimit: 17)
                ),
                issuedAt: Self.timestamp
            )
        )
        guard case let .settings(updatedSettings) = updated.result else {
            Issue.record("The settings update returned the wrong result type.")
            return
        }
        #expect(updatedSettings.version == 1)
        #expect(updatedSettings.values.statusListLimit == 17)

        do {
            _ = try await service.execute(
                AutomationCommandRequest(
                    commandID: AutomationCommandID(UUID()),
                    replayNonce: AutomationReplayNonce(UUID()),
                    command: .updateSettings(
                        try AutomationSettingsPatch(
                            expectedVersion: 0,
                            statusListLimit: 18
                        )
                    ),
                    issuedAt: Self.timestamp
                )
            )
            Issue.record("A stale settings CAS unexpectedly succeeded.")
        } catch let error as AutomationContractError {
            #expect(error == .settingsConflict)
        }
        #expect(try fixture.repository.currentAutomationSettings() == updatedSettings)

        let rollbackID = AutomationCommandID(UUID())
        let rolledBack = try await service.execute(
            AutomationCommandRequest(
                commandID: rollbackID,
                replayNonce: AutomationReplayNonce(UUID()),
                command: .rollbackSettings(
                    AutomationSettingsRollbackRequest(
                        targetCommandID: updateID,
                        expectedVersion: 1
                    )
                ),
                issuedAt: Self.timestamp
            )
        )
        guard case let .settings(rollbackSettings) = rolledBack.result else {
            Issue.record("The settings rollback returned the wrong result type.")
            return
        }
        #expect(rollbackSettings.version == 2)
        #expect(rollbackSettings.values == .compiledDefault)

        let cliOutput = await AutomationCLIAdapter(
            executor: service,
            clock: { Self.timestamp }
        ).run(arguments: ["settings", "get"])
        #expect(cliOutput.exitCode == .success)
        let cliBytes = try #require(cliOutput.standardOutput)
        let cliExecution = try JSONDecoder().decode(
            AutomationCommandExecution.self,
            from: Data(cliBytes.dropLast())
        )
        guard case let .settings(cliSettings) = cliExecution.result else {
            Issue.record("The CLI and application command layer diverged.")
            return
        }
        let repositorySettings = try fixture.repository.currentAutomationSettings()
        #expect(cliSettings == repositorySettings)

        let replayNonce = AutomationReplayNonce(UUID())
        let originalID = AutomationCommandID(UUID())
        _ = try await service.execute(
            AutomationCommandRequest(
                commandID: originalID,
                replayNonce: replayNonce,
                command: .getSettings,
                issuedAt: Self.timestamp
            )
        )
        let replayID = AutomationCommandID(UUID())
        do {
            _ = try await service.execute(
                AutomationCommandRequest(
                    commandID: replayID,
                    replayNonce: replayNonce,
                    command: .getWorkspaceStatus,
                    issuedAt: Self.timestamp
                )
            )
            Issue.record("A reused replay nonce unexpectedly executed.")
        } catch let error as AutomationContractError {
            #expect(error == .replayDetected(originalID))
        }

        let trails = try fixture.repository.automationActivity(
            limit: 20,
            excludingCommandID: nil
        )
        let replayTrail = trails.first { $0.record.commandID == replayID }
        #expect(replayTrail?.record.decision == .replayed)
        #expect(replayTrail?.record.replayOfCommandID == originalID)
        #expect(replayTrail?.resultEvents.first?.outcome == .rejected)
        let rollbackTrail = trails.first { $0.record.commandID == rollbackID }
        #expect(rollbackTrail?.resultEvents.first?.outcome == .rolledBack)
        #expect(rollbackTrail?.resultEvents.first?.rollbackOfCommandID == updateID)

        #expect(throws: (any Error).self) {
            try fixture.store.databasePool.write { db in
                try db.execute(
                    sql: "UPDATE automation_command_records SET safe_reason_code = 'changed' WHERE command_id = ?",
                    arguments: [originalID.canonicalString]
                )
            }
        }

        let recovery = SQLiteRecoveryService(
            store: fixture.store,
            storage: LocalStorageService(workspace: fixture.workspace)
        )
        let snapshot = try recovery.createRecoverySnapshot(createdAt: Self.timestamp)
        try recovery.verifyRecoverySnapshot(snapshot)
    }

    @Test
    func injectedSettingsProjectionFailureRollsBackTheWholeChange() async throws {
        let fixture = try TestAutomationFixture()
        defer { fixture.remove() }
        let service = try fixture.service(permission: .safeConfiguration)
        let commandID = AutomationCommandID(UUID())
        try await fixture.store.databasePool.write { db in
            try db.execute(
                sql: """
                CREATE TRIGGER test_reject_automation_settings_state
                BEFORE INSERT ON automation_settings_state
                BEGIN SELECT RAISE(ABORT, 'intentional settings projection failure'); END
                """
            )
        }
        do {
            _ = try await service.execute(
                AutomationCommandRequest(
                    commandID: commandID,
                    replayNonce: AutomationReplayNonce(UUID()),
                    command: .updateSettings(
                        try AutomationSettingsPatch(
                            expectedVersion: 0,
                            statusListLimit: 23
                        )
                    ),
                    issuedAt: Self.timestamp
                )
            )
            Issue.record("An injected settings transaction failure unexpectedly committed.")
        } catch let error as AutomationContractError {
            #expect(error == .persistenceFailure("automation_operation_failed"))
        }
        let facts = try await fixture.store.databasePool.read { db in
            (
                stateCount: try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM automation_settings_state"
                ),
                eventCount: try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM automation_settings_events"
                )
            )
        }
        #expect(facts.stateCount == 0)
        #expect(facts.eventCount == 0)
        #expect(try fixture.repository.currentAutomationSettings() == .compiledDefault)
        let trail = try #require(
            fixture.repository.automationActivity(
                limit: 5,
                excludingCommandID: nil
            ).first {
                $0.record.commandID == commandID
            }
        )
        #expect(trail.resultEvents.first?.outcome == .failed)
    }

    @Test
    func meetingPolicyRequiresCurrentGraphAndDiagnosticsUseRestrictedDirectory() async throws {
        let fixture = try TestAutomationFixture()
        defer { fixture.remove() }
        let service = try fixture.service(permission: .operational)
        let meeting = try fixture.insertPublishedMeeting()

        do {
            _ = try await service.execute(
                AutomationCommandRequest(
                    commandID: AutomationCommandID(UUID()),
                    replayNonce: AutomationReplayNonce(UUID()),
                    command: .getMeetingPolicyStatus(
                        AutomationMeetingPolicyRequest(meetingID: meeting.meetingID)
                    ),
                    issuedAt: Self.timestamp
                )
            )
            Issue.record("A meeting without a current policy graph unexpectedly passed.")
        } catch let error as AutomationContractError {
            #expect(error == .policyDenied("current_meeting_policy_unavailable"))
        }

        let policy = try fixture.insertDefaultSecurityPolicy(for: meeting)
        let statusExecution = try await service.execute(
            AutomationCommandRequest(
                commandID: AutomationCommandID(UUID()),
                replayNonce: AutomationReplayNonce(UUID()),
                command: .getMeetingPolicyStatus(
                    AutomationMeetingPolicyRequest(meetingID: meeting.meetingID)
                ),
                issuedAt: Self.timestamp
            )
        )
        guard case let .meetingPolicyStatus(status) = statusExecution.result else {
            Issue.record("The meeting policy command returned the wrong result type.")
            return
        }
        #expect(status.accessPolicyRevision.revisionID == policy.accessPolicy.revision.revisionID)
        #expect(status.noOutboundMode)
        #expect(status.modelRouteDisposition == .notApplicable)

        let diagnostics = try await service.execute(
            AutomationCommandRequest(
                commandID: AutomationCommandID(UUID()),
                replayNonce: AutomationReplayNonce(UUID()),
                command: .runWorkspaceDiagnostics(
                    try AutomationDiagnosticsRequest(maximumEntries: 1_000)
                ),
                issuedAt: Self.timestamp
            )
        )
        guard case let .diagnostics(report) = diagnostics.result else {
            Issue.record("The diagnostics command returned the wrong result type.")
            return
        }
        #expect(report.databaseQuickCheckPassed)
        #expect(report.foreignKeyFailureCount == 0)
        #expect(report.usedRestrictedTaskDirectory)
        let taskEntries = try FileManager.default.contentsOfDirectory(
            at: fixture.workspace.layout.tasks,
            includingPropertiesForKeys: nil
        )
        #expect(taskEntries.isEmpty)
        let diagnosticTrail = try fixture.repository.automationActivity(
            limit: 5,
            excludingCommandID: nil
        )
            .first { $0.record.commandName == .runWorkspaceDiagnostics }
        #expect(diagnosticTrail?.resultEvents.first?.usedRestrictedTaskDirectory == true)
    }

    private static let timestamp = try! UTCInstant(millisecondsSinceUnixEpoch: 1_800_000_000_000)
}

private actor CountingExecutor: AutomationCommandExecuting {
    private(set) var executionCount = 0

    func execute(_ request: AutomationCommandRequest) async throws -> AutomationCommandExecution {
        executionCount += 1
        return AutomationCommandExecution(
            commandID: request.commandID,
            commandName: request.command.name,
            result: .commandCatalog(AutomationCommandCatalog())
        )
    }
}

final class TestAutomationFixture {
    static let timestamp = try! UTCInstant(millisecondsSinceUnixEpoch: 1_800_000_000_000)

    let root: URL
    let workspace: LocalWorkspaceDescriptor
    let store: SQLitePersistenceStore
    let repository: SQLiteAutomationRepository

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingBuddyAutomationTests-\(UUID().uuidString)")
        workspace = try LocalWorkspaceService().createWorkspace(
            at: root,
            workspaceID: WorkspaceID(UUID()),
            createdAt: Self.timestamp
        )
        store = try SQLitePersistenceStore(
            workspace: workspace,
            migrationTimestamp: Self.timestamp
        )
        repository = SQLiteAutomationRepository(store: store)
    }

    func service(
        permission: AutomationPermission,
        rootCommandID: AutomationCommandID? = nil,
        parentCommandID: AutomationCommandID? = nil,
        hopCount: UInt8 = 0
    ) throws -> AutomationCommandService {
        let caller = try AutomationCallerContext(
            workspaceID: workspace.manifest.workspaceID,
            actorID: AutomationActorID("automation_test"),
            origin: .application,
            maximumPermission: permission,
            adapterVersion: "test_v1",
            ancestorBoundaries: hopCount == 0 ? [] : [.meetingBuddy],
            rootCommandID: rootCommandID,
            parentCommandID: parentCommandID,
            hopCount: hopCount
        )
        return AutomationCommandService(
            repository: repository,
            temporaryStorage: LocalTaskTemporaryStorage(workspace: workspace),
            caller: caller,
            clock: { Self.timestamp }
        )
    }

    func insertPublishedMeeting() throws -> MeetingProfileV1 {
        let meetingID = MeetingID(UUID())
        let revisionID = RevisionID(UUID())
        let draftEnvelope = try RevisionEnvelope(
            logicalID: meetingID,
            revisionID: revisionID,
            schemaVersion: .v1,
            lifecycleStatus: .draft,
            validationState: .notValidated,
            createdAt: Self.timestamp,
            createdBy: .application,
            dataClassification: .sensitive
        )
        let draft = try meeting(envelope: draftEnvelope)
        let publishedEnvelope = try RevisionEnvelope(
            logicalID: meetingID,
            revisionID: revisionID,
            schemaVersion: .v1,
            lifecycleStatus: .published,
            validationState: .valid,
            createdAt: Self.timestamp,
            createdBy: .application,
            publishedAt: Self.timestamp,
            dataClassification: .sensitive,
            semanticContentHash: draft.calculatedSemanticContentHash()
        )
        let published = try meeting(envelope: publishedEnvelope)
        try store.insert(published)
        try store.activate(
            ActivePublishedRevisionSelection(
                logicalID: meetingID,
                revisionID: revisionID
            ),
            as: MeetingProfileV1.self,
            expectedCurrentRevisionID: nil,
            markedAt: Self.timestamp
        )
        return published
    }

    func insertDefaultSecurityPolicy(
        for meeting: MeetingProfileV1
    ) throws -> LocalSecurityPolicyBundle {
        let bundle = try LocalSecurityPolicyFactory().makeDefault(
            meeting: meeting,
            sensitivityLabelID: SensitivityLabelID(UUID()),
            sensitivityLabelRevisionID: RevisionID(UUID()),
            accessPolicyID: AccessPolicyID(UUID()),
            accessPolicyRevisionID: RevisionID(UUID()),
            createdAt: Self.timestamp
        )
        try store.insert(bundle.sensitivityLabel)
        try store.activate(
            ActivePublishedRevisionSelection(
                logicalID: bundle.sensitivityLabel.labelID,
                revisionID: bundle.sensitivityLabel.revision.revisionID
            ),
            as: SensitivityLabelV1.self,
            expectedCurrentRevisionID: nil,
            markedAt: Self.timestamp
        )
        try store.insert(bundle.accessPolicy)
        try store.activate(
            ActivePublishedRevisionSelection(
                logicalID: bundle.accessPolicy.policyID,
                revisionID: bundle.accessPolicy.revision.revisionID
            ),
            as: AccessPolicyV1.self,
            expectedCurrentRevisionID: nil,
            markedAt: Self.timestamp
        )
        return bundle
    }

    func remove() {
        try? store.close()
        try? FileManager.default.removeItem(at: root)
    }

    private func meeting(
        envelope: RevisionEnvelope<MeetingIDTag>
    ) throws -> MeetingProfileV1 {
        try MeetingProfileV1(
            revision: envelope,
            title: "Automation policy fixture",
            sourceLanguages: [LanguageTag("en")],
            outputLanguage: LanguageTag("en"),
            cloudProcessingPolicy: .localOnly,
            workspaceID: workspace.manifest.workspaceID,
            reviewStatus: .unreviewed,
            userConfirmed: false
        )
    }
}

import Foundation
import MeetingBuddyApplication
import SwiftUI

struct LearnedPreferencesSettingsPane: View {
    @Bindable var store: MediaReviewStore
    @Bindable var editorState:
        LearnedPreferenceEditorState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                EditorialSectionHeader(
                    "Learned Presentation Preferences",
                    detail:
                        "Review explicit, repository-backed presentation guidance and its immutable content-free audit trail."
                )
                authorityBoundary
                if store.workspace == nil {
                    unavailableState
                } else if
                    store.learnedPreferencesAreLoading
                {
                    loadingState
                    if let state =
                        store.learnedPreferences
                    {
                        lastSuccessfulState(
                            "Reloading from the repository. This snapshot is read-only until the refresh completes."
                        )
                        preferenceLedger(
                            state,
                            allowsChanges: false
                        )
                    }
                } else if let failure =
                    store
                    .learnedPreferencesFailureMessage
                {
                    failedState(
                        failure,
                        retainsSnapshot:
                            store.learnedPreferences != nil
                    )
                    if let state =
                        store.learnedPreferences
                    {
                        preferenceLedger(
                            state,
                            allowsChanges: false
                        )
                    }
                    reloadButton
                } else if let state =
                    store.learnedPreferences
                {
                    preferenceLedger(
                        state,
                        allowsChanges: true
                    )
                    editor
                } else {
                    notLoadedState
                }
            }
            .padding(20)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
        .task(id: store.workspaceReadySession) {
            editorState.reset()
            await store.loadLearnedPreferences()
        }
        .confirmationDialog(
            "Reset all learned preferences?",
            isPresented:
                $editorState
                .isResetConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(
                "Reset All",
                role: .destructive
            ) {
                Task {
                    await store.resetLearnedPreferences(
                        confirmedByVisibleDialog: true,
                        using: editorState
                    )
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "All active and disabled preference values will be removed. Content-free action and digest audit events remain visible, but cannot restore a preference value."
            )
        }
        .accessibilityIdentifier(
            "blueminutes.settings.learned-preferences"
        )
    }

    private var authorityBoundary: some View {
        WorkflowStateView(
            title: "Presentation guidance only",
            detail:
                "Preferences are created only from explicit actions. They affect presentation, never access policy, model routing, evidence requirements, classification, provider authority, external routes, or protected diplomatic rules.",
            systemImage: "text.badge.checkmark",
            tone: .neutral
        )
    }

    private var unavailableState: some View {
        WorkflowStateView(
            title: "No local workspace is open",
            detail:
                "Choose a workspace in the main BlueMinutes window before reviewing its learned preferences.",
            systemImage: "folder.badge.questionmark",
            tone: .warning
        )
    }

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(
                "Loading learned preferences from the selected local workspace…"
            )
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Loading learned presentation preferences"
        )
    }

    private var notLoadedState: some View {
        WorkflowStateView(
            title: "Preferences are not loaded",
            detail:
                "Reload the repository-backed preference state for the selected local workspace.",
            systemImage: "arrow.clockwise.circle",
            tone: .neutral
        )
        .overlay(alignment: .bottomTrailing) {
            Button("Reload Preferences") {
                Task {
                    await store
                        .loadLearnedPreferences()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.bottom, 38)
    }

    private func failedState(
        _ message: String,
        retainsSnapshot: Bool
    ) -> some View {
        WorkflowStateView(
            title: retainsSnapshot
                ? "Last successful preference snapshot"
                : "Learned preferences unavailable",
            detail: retainsSnapshot
                ? "The latest repository operation failed. The ledger below is retained only as the last successful snapshot and is read-only. \(message)"
                : message,
            systemImage:
                "exclamationmark.triangle",
            tone: .failure
        )
    }

    private func lastSuccessfulState(
        _ detail: String
    ) -> some View {
        WorkflowStateView(
            title: "Last successful preference snapshot",
            detail: detail,
            systemImage:
                "clock.arrow.trianglehead.counterclockwise.rotate.90",
            tone: .warning
        )
    }

    private var reloadButton: some View {
        Button("Reload Preferences") {
            Task {
                await store.loadLearnedPreferences()
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(store.isWorking)
        .accessibilityLabel(
            "Reload learned preferences from the local repository"
        )
    }

    private func preferenceLedger(
        _ state: LearnedPreferenceState,
        allowsChanges: Bool
    ) -> some View {
        GroupBox("Learned Preferences") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(
                    "Apply learned preferences",
                    isOn: Binding(
                        get: {
                            state.globallyEnabled
                        },
                        set: { enabled in
                            Task {
                                await store
                                    .setLearnedPreferencesGloballyEnabled(
                                        enabled
                                    )
                            }
                        }
                    )
                )
                .disabled(
                    store.isWorking || !allowsChanges
                )
                .accessibilityIdentifier(
                    "blueminutes.settings.learned-preferences.global-toggle"
                )
                .accessibilityHint(
                    "Disabled preferences remain visible and editable but do not affect presentation."
                )

                if state.preferences.isEmpty {
                    ContentUnavailableView(
                        "No Learned Preferences",
                        systemImage:
                            "text.badge.plus",
                        description: Text(
                            "No explicit presentation preference is stored in this workspace."
                        )
                    )
                } else {
                    ForEach(
                        state.preferences
                    ) { preference in
                        preferenceRow(
                            preference,
                            allowsChanges:
                                allowsChanges
                        )
                        Divider()
                    }
                }

                if !state.recentEvents.isEmpty {
                    preferenceAudit(state)
                }
            }
            .padding()
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
    }

    private func preferenceAudit(
        _ state: LearnedPreferenceState
    ) -> some View {
        DisclosureGroup(
            "Recent Preference Audit"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(state.recentEvents) { event in
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(event.action.rawValue)
                            .font(
                                .caption.weight(
                                    .semibold
                                )
                            )
                        Text(
                            "Source: \(event.sourceAction); recorded \(event.recordedAt.millisecondsSinceUnixEpoch)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if let prior =
                            event.priorValueDigest
                        {
                            Text(
                                "Prior digest: \(prior.lowercaseHex)"
                            )
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        }
                        if let replacement =
                            event
                            .replacementValueDigest
                        {
                            Text(
                                "Replacement digest: \(replacement.lowercaseHex)"
                            )
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        }
                    }
                    .accessibilityElement(
                        children: .combine
                    )
                    .accessibilityLabel(
                        "Preference audit action \(event.action.rawValue), source \(event.sourceAction)"
                    )
                }
            }
            .padding(.top, 6)
        }
        .accessibilityHint(
            "Shows immutable action metadata and digests, never deleted raw preference values."
        )
    }

    private var editor: some View {
        GroupBox(
            editorState.editingPreferenceID == nil
                ? "Add Preference"
                : "Edit Preference"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Picker(
                    "Preference type",
                    selection: $editorState.kind
                ) {
                    ForEach(
                        LearnedPreferenceKind.allCases,
                        id: \.rawValue
                    ) { kind in
                        Text(
                            LearnedPreferencePresentation
                                .label(kind)
                        )
                        .tag(kind)
                    }
                }
                .accessibilityIdentifier(
                    "blueminutes.settings.learned-preferences.kind"
                )
                TextField(
                    LearnedPreferencePresentation
                        .prompt(editorState.kind),
                    text: $editorState.value
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(
                    "Learned preference value"
                )
                .accessibilityIdentifier(
                    "blueminutes.settings.learned-preferences.value"
                )

                HStack {
                    Button(
                        editorState
                            .editingPreferenceID
                            == nil
                            ? "Add Preference"
                            : "Save Edit"
                    ) {
                        Task {
                            await store
                                .saveLearnedPreference(
                                    using: editorState
                                )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(
                        "blueminutes.settings.learned-preferences.save"
                    )
                    .disabled(
                        store.isWorking
                            || editorState.value
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                            .isEmpty
                    )

                    Button(
                        "Reset All…",
                        role: .destructive
                    ) {
                        editorState
                            .isResetConfirmationPresented =
                            true
                    }
                    .disabled(
                        store.isWorking
                            || store.learnedPreferences?
                            .preferences.isEmpty != false
                    )
                    .accessibilityIdentifier(
                        "blueminutes.settings.learned-preferences.reset"
                    )
                }
            }
            .padding()
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
    }

    private func preferenceRow(
        _ record: LearnedPreferenceRecord,
        allowsChanges: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        LearnedPreferencePresentation
                            .label(record.kind)
                    )
                    .font(
                        .subheadline.weight(.semibold)
                    )
                    Label(
                        record.enabled
                            ? "Enabled"
                            : "Disabled",
                        systemImage:
                            record.enabled
                            ? "checkmark.circle"
                            : "pause.circle"
                    )
                    .foregroundStyle(
                        record.enabled
                            ? .green
                            : .secondary
                    )
                }
                Spacer()
                Button("Edit") {
                    store.editLearnedPreference(
                        record,
                        using: editorState
                    )
                }
                .accessibilityLabel(
                    "Edit \(LearnedPreferencePresentation.label(record.kind)) preference"
                )
                .accessibilityIdentifier(
                    preferenceActionIdentifier(
                        record,
                        action: "edit"
                    )
                )
                Button(
                    record.enabled
                        ? "Disable"
                        : "Enable"
                ) {
                    Task {
                        await store
                            .toggleLearnedPreference(
                                record
                            )
                    }
                }
                .accessibilityLabel(
                    "\(record.enabled ? "Disable" : "Enable") \(LearnedPreferencePresentation.label(record.kind)) preference"
                )
                .accessibilityIdentifier(
                    preferenceActionIdentifier(
                        record,
                        action:
                            record.enabled
                            ? "disable"
                            : "enable"
                    )
                )
                Button(
                    "Remove",
                    role: .destructive
                ) {
                    Task {
                        await store
                            .removeLearnedPreference(
                                record,
                                using: editorState
                            )
                    }
                }
                .accessibilityLabel(
                    "Remove \(LearnedPreferencePresentation.label(record.kind)) preference"
                )
                .accessibilityIdentifier(
                    preferenceActionIdentifier(
                        record,
                        action: "remove"
                    )
                )
            }
            Text(record.value.displaySummary)
                .textSelection(.enabled)
            Text(
                "Source: \(record.sourceAction); version \(record.version); updated \(record.updatedAt.millisecondsSinceUnixEpoch)"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .disabled(
            store.isWorking || !allowsChanges
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(LearnedPreferencePresentation.label(record.kind)), \(record.enabled ? "enabled" : "disabled")"
        )
    }

    private func preferenceActionIdentifier(
        _ record: LearnedPreferenceRecord,
        action: String
    ) -> String {
        "blueminutes.settings.learned-preferences.preference."
            + record.preferenceID.canonicalString
            + "."
            + action
    }
}

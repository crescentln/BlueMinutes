import Foundation
import SwiftUI
@testable import MeetingBuddyFeatures

@MainActor
enum BlueMinutesProductionVisualFixtureFactory {
    static func content(
        for fixture:
            BlueMinutesVisualFixtureCase
    ) async throws ->
        BlueMinutesProductionVisualContent
    {
        switch (
            fixture.surface,
            fixture.descriptor.state
        ) {
        case (.shell, _):
            let state =
                try await
                makeFeatureOpenedVisualFixture()
            return hosted(
                MeetingBuddyRootView(
                    store: state.store
                ) {
                    sceneState in
                    sceneState.selectedSection =
                        .intake
                },
                editorialBackground: false
            )
        case (.onboarding, _):
            let store =
                try makeFeatureStoreForHostedSettingsTests()
            return hosted(
                MeetingBuddyRootView(
                    store: store
                ),
                editorialBackground: false
            )
        case (.localMedia, let stateName):
            let state =
                stateName == "working"
                ? try await
                    makeFeatureLocalMediaWorkingVisualFixture()
                : try await
                    makeFeatureLocalMediaVisualFixture()
            return hosted(
                LocalMediaIntakeView(
                    store: state.store,
                    sceneState:
                        state.sceneState,
                    chooseMedia: {},
                    requestImport: {}
                )
            )
        case (.recording, let stateName):
            if stateName == "loading" {
                let state =
                    try await
                    makeFeatureRecordingLoadingVisualFixture()
                return hosted(
                    RecordingCaptureView(
                        store: state.store,
                        sceneState:
                            state.sceneState
                    )
                ) {
                    await state.setupGate
                        .release()
                    await state.openTask.value
                }
            }
            let state = try await {
                return try await
                    makeFeatureRecordingVisualFixture(
                        active:
                            stateName == "active"
                    )
            }()
            return hosted(
                RecordingCaptureView(
                    store: state.store,
                    sceneState:
                        state.sceneState
                )
            )
        case (.unWebTV, let stateName):
            let state =
                stateName == "candidate"
                ? try await
                    makeFeatureUNWebTVCandidateVisualFixture()
                : try await
                    makeFeatureOpenedVisualFixture()
            return hosted(
                UNWebTVMetadataView(
                    store: state.store,
                    sceneState:
                        state.sceneState
                )
            )
        case (.transcript, let stateName):
            let state =
                try await
                makeFeatureReviewVisualFixture(
                    transcriptIncomplete:
                        stateName == "incomplete"
                )
            return hosted(
                TranscriptReviewView(
                    store: state.store,
                    sceneState:
                        state.sceneState,
                    initialInspectorIsPresented:
                        fixture.descriptor
                        .inspectorPresented
                )
            )
        case (.analysis, let stateName):
            let state =
                try await
                makeFeatureReviewVisualFixture(
                    analysisStale:
                        stateName == "stale"
                )
            let bundle =
                state.store
                .analysisReview
            let selection:
                AnalysisEvidenceSelection? =
                bundle.flatMap {
                    bundle in
                    guard
                        let position =
                            bundle
                            .positions
                            .first,
                        let reference =
                            position
                            .statement
                            .evidenceRevisions
                            .first
                    else {
                        return nil
                    }
                    return
                        AnalysisEvidenceSelection(
                            context:
                                "Selected Position Evidence",
                            claim:
                                position
                                .statement,
                            evidenceReference:
                                reference
                        )
                }
            return hosted(
                AnalysisReviewView(
                    store: state.store,
                    sceneState:
                        state.sceneState,
                    initialInspectorIsPresented:
                        fixture.descriptor
                        .inspectorPresented,
                    initialEvidenceSelection:
                        selection
                )
            )
        case (.briefing, let stateName):
            let state =
                try await
                makeFeatureReviewVisualFixture(
                    briefingHumanConfirmed:
                        stateName
                        == "selected"
                )
            return hosted(
                BriefingReviewView(
                    store: state.store,
                    sceneState:
                        state.sceneState
                )
            )
        case (.history, let stateName):
            let state =
                try await
                makeFeatureHistoryVisualFixture(
                    withResults:
                        stateName == "results"
                )
            return hosted(
                HistoricalReviewView(
                    store: state.store,
                    sceneState:
                        state.sceneState
                )
            )
        case (.storage, let stateName):
            let store =
                try await
                makeFeatureStorageVisualFixture(
                    destructiveDisabled:
                        stateName
                        == "destructive-disabled",
                    failure:
                        stateName
                        == "failure"
                )
            return hosted(
                StorageDashboardView(
                    store: store,
                    requestPermanentDeletion:
                        { _ in }
                )
            )
        case (.settings, let stateName):
            let suiteName =
                "org.blueminutes.visual.\(fixture.id)"
            guard let defaults =
                UserDefaults(
                    suiteName:
                        suiteName
                )
            else {
                throw
                    BlueMinutesProductionVisualFixtureError
                    .defaultsUnavailable
            }
            defaults.removePersistentDomain(
                forName: suiteName
            )
            return hosted(
                BlueMinutesSettingsView(
                    defaults: defaults,
                    initialTab:
                        stateName
                        == "appearance"
                        ? .appearance
                        : .general
                ),
                editorialBackground: false
            )
        }
    }

    private static func hosted<Content: View>(
        _ content: Content,
        editorialBackground:
            Bool = true,
        teardown:
            @escaping @MainActor
            () async -> Void = {}
    ) -> BlueMinutesProductionVisualContent {
        let view: AnyView
        if editorialBackground {
            view =
                AnyView(
                    content
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .topLeading
                        )
                        .background(
                            BlueMinutesColors.canvas
                        )
                )
        } else {
            view = AnyView(content)
        }
        return BlueMinutesProductionVisualContent(
            view: view,
            teardown: teardown
        )
    }
}

struct BlueMinutesProductionVisualContent {
    let view: AnyView
    let teardown:
        @MainActor
        () async -> Void
}

private enum BlueMinutesProductionVisualFixtureError:
    Error
{
    case defaultsUnavailable
}

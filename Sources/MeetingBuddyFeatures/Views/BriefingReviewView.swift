import MeetingBuddyApplication
import MeetingBuddyDomain
import Observation
import SwiftUI

struct BriefingReviewView: View {
    @Bindable var store: MediaReviewStore
    @Bindable var sceneState: MediaReviewSceneState

    var body: some View {
        Group {
            if let review = store.briefingReview {
                reviewWorkspace(review)
            } else {
                setupView
            }
        }
        .onAppear {
            reconcileBriefingDraft()
        }
        .onChange(
            of: sceneState.briefing.selectedSectionType
        ) { _, _ in
            reconcileBriefingDraft()
        }
        .onChange(
            of: store.briefingReview?.publication
                .sections.map(\.revision.revisionID)
        ) { _, _ in
            reconcileBriefingDraft()
        }
    }

    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                EditorialSectionHeader(
                    "Create a Briefing",
                    detail:
                        "Generate exactly three independent on-device sections from the validated Analysis publication."
                )
                routeCard
                if let job = store.briefingJob {
                    jobCard(job)
                }
                generationCard
            }
            .padding(28)
            .frame(maxWidth: 920, alignment: .leading)
        }
    }

    private var routeCard: some View {
        GroupBox("Briefing privacy route") {
            VStack(alignment: .leading, spacing: 9) {
                if let route = store.briefingRouteReview {
                    LabeledContent(
                        "Route",
                        value:
                            route.briefing.route
                                == .appleOnDevice
                            ? "Apple Foundation Models on device"
                            : "No automatic local model"
                    )
                    LabeledContent(
                        "Destination",
                        value: "this Mac"
                    )
                    LabeledContent(
                        "Provider inputs",
                        value:
                            route.briefing.request
                            .dataCategories
                            .map(\.rawValue)
                            .joined(separator: ", ")
                    )
                    LabeledContent(
                        "Policy decision",
                        value: route.briefing.reasonCode
                    )
                    LabeledContent(
                        "Runtime",
                        value:
                            "\(route.runtimeEvidence.operatingSystemVersion) · \(route.runtimeEvidence.adapterVersion)"
                    )
                } else {
                    Label(
                        "Check the local model after validating analysis",
                        systemImage: "lock.shield"
                    )
                }
                Divider()
                Text(
                    "No raw transcript, audio, cloud adapter, network tool, credential, or provider-retention path is added by this workflow."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private var generationCard: some View {
        GroupBox("Validated diplomatic briefing") {
            VStack(alignment: .leading, spacing: 12) {
                WorkflowStateView(
                    title: "Explicit local generation",
                    detail:
                        "Generate Briefing authorizes three independent on-device section runs over validated intelligence claims and evidence identifiers. Publication is atomic and fails closed unless every source segment and conclusion is traceable.",
                    systemImage:
                        "doc.text.magnifyingglass",
                    tone: .neutral
                )
                HStack {
                    Button(
                        "Check Local Briefing Model"
                    ) {
                        Task {
                            await store
                                .refreshBriefingRoute()
                        }
                    }
                    .disabled(store.isWorking)

                    Button("Generate Briefing") {
                        Task {
                            await store.startBriefing()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        store.briefingRouteReview?
                            .isOnDeviceReady != true
                            || store.isWorking
                    )
                }
            }
            .padding()
        }
    }

    private func jobCard(
        _ job: MediaJobReview
    ) -> some View {
        GroupBox("Local briefing task") {
            VStack(alignment: .leading, spacing: 9) {
                LabeledContent(
                    "State",
                    value: label(job.state.rawValue)
                )
                ProgressView(value: job.progressFraction)
                LabeledContent(
                    "Independent sections",
                    value:
                        "\(job.completedUnitCount) / \(job.totalUnitCount)"
                )
                if let failure = job.safeFailureSummary {
                    Text(failure)
                        .foregroundStyle(
                            BlueMinutesColors.error
                        )
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func reviewWorkspace(
        _ review: BriefingReviewBundle
    ) -> some View {
        if let sections = canonicalSections(in: review) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    reviewState(review)
                    BriefingEditorialCanvas(
                        review: review,
                        sections: sections,
                        selectSection: {
                            sceneState
                                .requestBriefingSelection($0)
                        }
                    )
                    sectionEditor(
                        review,
                        sections: sections
                    )
                    BriefingPublicationProofView(
                        review: review
                    )
                    markdownPreview(review)
                    exportCard(review)
                }
                .padding(24)
                .frame(
                    maxWidth: 1_080,
                    alignment: .leading
                )
            }
        } else {
            WorkflowStateView(
                title:
                    "Briefing projection failed closed",
                detail:
                    "The publication does not expose one unique Meeting Overview, Major Issues, and Major Delegations section in canonical order.",
                systemImage: "exclamationmark.triangle",
                tone: .failure
            )
            .padding(28)
        }
    }

    @ViewBuilder
    private func reviewState(
        _ review: BriefingReviewBundle
    ) -> some View {
        if !review.isCurrent {
            WorkflowStateView(
                title:
                    "This briefing is stale after an upstream correction",
                detail:
                    "Published content remains readable, but section save, regeneration, and export stay blocked until the existing application workflow produces a current Briefing publication.",
                systemImage:
                    "exclamationmark.triangle.fill",
                tone: .warning
            )
            .accessibilityLabel("Stale briefing warning")
        }
        if !review.isHumanConfirmed {
            WorkflowStateView(
                title: "Quarantined generated briefing",
                detail:
                    "Review and explicitly confirm every current section before export.",
                systemImage:
                    "exclamationmark.shield.fill",
                tone: .warning
            )
            .accessibilityLabel(
                "Unconfirmed briefing warning"
            )
        }
    }

    private func sectionEditor(
        _ review: BriefingReviewBundle,
        sections: [BriefingSectionV1]
    ) -> some View {
        BriefingSectionEditor(
            review: review,
            sections: sections,
            selectedSectionType:
                briefingSelection,
            draftItemTexts:
                $sceneState.briefing.itemTexts,
            draftIsLocked:
                $sceneState.briefing.isLocked,
            draftSourceIsCurrent:
                sceneState.briefing
                .isSourceRevisionCurrent,
            draftIsDirty:
                sceneState.briefing.isDirty,
            storeIsWorking: store.isWorking,
            briefingJobIsActive:
                store.briefingJob?
                .state.isTerminal == false,
            interactionIsLocked:
                sceneState.isInteractionLocked,
            navigationIsPending:
                sceneState
                .isNavigationConfirmationPresented,
            save: saveSection,
            regenerate: regenerateSection
        )
    }

    private func markdownPreview(
        _ review: BriefingReviewBundle
    ) -> some View {
        DisclosureGroup(
            review.isHumanConfirmed
                ? "Human-confirmed Markdown preview"
                : "Quarantined Markdown preview"
        ) {
            ScrollView(.horizontal) {
                Text(
                    review.publication.finalBriefing
                        .markdown
                )
                .textSelection(.enabled)
                .font(
                    .system(
                        .callout,
                        design: .monospaced
                    )
                )
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
            }
            .frame(maxHeight: 320)
            .padding(.top, 10)
        }
    }

    private func exportCard(
        _ review: BriefingReviewBundle
    ) -> some View {
        let availability = exportAvailability(review)
        return GroupBox(
            "Explicit local Markdown export"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if availability.canExport {
                    WorkflowStateView(
                        title: "Validated export ready",
                        detail:
                            "Export writes the exact confirmed Markdown through the existing application-owned workflow.",
                        systemImage: "checkmark.seal",
                        tone: .ready
                    )
                } else {
                    WorkflowStateView(
                        title: "Export blocked",
                        detail: exportBlockReason(review),
                        systemImage: "lock.fill",
                        tone: .warning
                    )
                }
                TextField(
                    "File name",
                    text:
                        $sceneState
                        .briefingExportFileName
                )
                LabeledContent(
                    "Destination",
                    value:
                        "Meetings/\(review.publication.finalBriefing.meetingID.canonicalString)/exports/"
                )
                Button("Export Validated Markdown") {
                    Task {
                        await store.exportBriefing(
                            using: sceneState
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!availability.canExport)
                if let record = store.lastBriefingExport {
                    Label(
                        record.relativePath.rawValue,
                        systemImage:
                            "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                    .textSelection(.enabled)
                }
            }
            .padding()
        }
    }

    private func canonicalSections(
        in review: BriefingReviewBundle
    ) -> [BriefingSectionV1]? {
        let sections = review.publication.sections.sorted {
            ($0.order, $0.sectionID.canonicalString)
                < ($1.order, $1.sectionID.canonicalString)
        }
        guard BriefingSectionProjection.isCanonical(
            sectionTypes: sections.map(\.sectionType),
            orders: sections.map(\.order),
            uniqueLogicalIDCount:
                Set(sections.map(\.sectionID)).count
        ) else {
            return nil
        }
        return sections
    }

    private var briefingSelection:
        Binding<BriefingSectionType?>
    {
        Binding(
            get: {
                sceneState.briefing
                    .selectedSectionType
            },
            set: {
                sceneState
                    .requestBriefingSelection($0)
            }
        )
    }

    private func exportAvailability(
        _ review: BriefingReviewBundle
    ) -> BriefingReviewActionAvailability {
        BriefingReviewActionAvailability(
            publicationIsCurrent: review.isCurrent,
            publicationIsHumanConfirmed:
                review.isHumanConfirmed,
            draftIsComplete: true,
            draftIsDirty:
                sceneState.briefing.isDirty,
            draftSourceIsCurrent:
                sceneState.briefing
                .isSourceRevisionCurrent,
            sectionIsLocked: false,
            sectionIsUserEdited: false,
            storeIsWorking: store.isWorking,
            briefingJobIsActive:
                store.briefingJob?
                .state.isTerminal == false,
            interactionIsLocked:
                sceneState.isInteractionLocked,
            navigationIsPending:
                sceneState
                .isNavigationConfirmationPresented
        )
    }

    private func exportBlockReason(
        _ review: BriefingReviewBundle
    ) -> String {
        if !review.isCurrent
            && !review.isHumanConfirmed
        {
            return
                "The publication is stale and all three current sections are not yet explicitly confirmed."
        }
        if !review.isCurrent {
            return
                "The publication is stale after an upstream correction."
        }
        if sceneState.briefing.isDirty {
            return
                "Save or discard the local section draft before exporting the published document."
        }
        if !sceneState.briefing
            .isSourceRevisionCurrent
        {
            return
                "The local draft is based on an earlier section revision."
        }
        if !review.isHumanConfirmed {
            return
                "All three sections need explicit user-confirmed revisions."
        }
        return
            "Wait for the current local operation to finish."
    }

    private func reconcileBriefingDraft() {
        sceneState.briefing.reconcile(
            with: store.briefingReview
        )
    }

    private func saveSection() {
        guard let operation =
            sceneState.beginDirectBriefingSave()
        else {
            return
        }
        Task {
            let succeeded = await store.saveEditorDraft(
                operation.request
            )
            if sceneState.completeDirectEditorSave(
                operation,
                succeeded: succeeded,
                updatedReviews:
                    store.editorReviewSnapshot
            ) {
                reconcileBriefingDraft()
            }
        }
    }

    private func regenerateSection(
        _ sectionType: BriefingSectionType
    ) {
        Task {
            await store.regenerateBriefingSection(
                sectionType
            )
        }
    }

    private func label(
        _ rawValue: String
    ) -> String {
        rawValue
            .replacingOccurrences(
                of: "_",
                with: " "
            )
            .capitalized
    }
}

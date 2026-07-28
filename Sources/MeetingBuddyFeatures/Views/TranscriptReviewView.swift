import MeetingBuddyApplication
import MeetingBuddyDomain
import Observation
import SwiftUI

struct TranscriptReviewView: View {
    @Bindable var store: MediaReviewStore
    @Bindable var sceneState: MediaReviewSceneState
    @State private var inspectorIsPresented = false
    @State private var inspectorEvidenceRevisionID:
        RevisionID?
    @State private var presentationCache:
        TranscriptReviewPresentationCache?
    @State private var transcriptSearchQuery =
        ""
    @State private var transcriptOutlineScope:
        TranscriptOutlineScope = .all
    @FocusState private var focusedEditor: TranscriptEditorFocus?
    private let intelligenceStore:
        IntelligenceConfigurationStore?
    private let inspectorPresentationOverride:
        Binding<Bool>?

    init(
        store: MediaReviewStore,
        sceneState:
            MediaReviewSceneState,
        intelligenceStore:
            IntelligenceConfigurationStore? = nil,
        initialInspectorIsPresented:
            Bool = false,
        inspectorPresentationOverride:
            Binding<Bool>? = nil
    ) {
        self.store = store
        self.sceneState = sceneState
        self.intelligenceStore =
            intelligenceStore
        self.inspectorPresentationOverride =
            inspectorPresentationOverride
        _inspectorIsPresented =
            State(
                initialValue:
                    initialInspectorIsPresented
            )
    }

    private var inspectorPresentation:
        Binding<Bool>
    {
        inspectorPresentationOverride
            ?? $inspectorIsPresented
    }

    private var inspectorPresented: Bool {
        inspectorPresentation
            .wrappedValue
    }

    private func presentInspector() {
        inspectorPresentation
            .wrappedValue = true
    }

    private func toggleInspector() {
        inspectorPresentation
            .wrappedValue.toggle()
    }

    var body: some View {
        Group {
            if let review = store.transcriptReview {
                reviewWorkspace(review)
            } else {
                setupView
            }
        }
        .onAppear {
            sceneState.transcript.reconcile(
                with: store.transcriptReview
            )
        }
        .onChange(
            of: sceneState.transcript.selectedSegmentID
        ) { _, _ in
            inspectorEvidenceRevisionID = nil
            sceneState.transcript.reconcile(
                with: store.transcriptReview
            )
        }
        .onChange(
            of:
                store.transcriptReview?.transcriptSegments.map(
                    \.revision.revisionID
                )
        ) { _, _ in
            sceneState.transcript.reconcile(
                with: store.transcriptReview
            )
        }
        .onChange(
            of:
                store.transcriptReview?.translations.map(
                    \.revision.revisionID
                )
        ) { _, _ in
            sceneState.transcript.reconcile(
                with: store.transcriptReview
            )
        }
    }

    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                routeCard
                GroupBox("Speech-to-Text Route") {
                    SpeechToTextRoutePicker(
                        sceneState: sceneState,
                        intelligenceStore:
                            intelligenceStore,
                        existingMeeting: true,
                        requiresExecutionAuthorization:
                            true
                    )
                    .padding()
                }
                GroupBox("Languages") {
                    Form {
                        TextField(
                            "Source language",
                            text:
                                $sceneState
                                .transcriptSourceLanguageTag
                        )
                        TextField(
                            "Target language (optional)",
                            text:
                                $sceneState
                                .transcriptTargetLanguageTag
                        )
                    }
                    .formStyle(.grouped)
                    HStack {
                        Button("Check STT Route") {
                            Task {
                                await store
                                    .refreshTranscriptRoute(
                                        using: sceneState
                                    )
                            }
                        }
                        Button("Start Transcription") {
                            Task {
                                await store.startTranscript(
                                    using: sceneState
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            sceneState
                                .transcriptionSelection
                                == nil
                                || store.isWorking
                        )
                    }
                    .padding([.horizontal, .bottom])
                }
                if let job = store.transcriptJob {
                    transcriptJobCard(job)
                }
                manualFallbackCard
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }

    private var routeCard: some View {
        GroupBox("Privacy route") {
            VStack(alignment: .leading, spacing: 10) {
                if let route = store.routeReview {
                    routeLine(
                        "Transcription",
                        decision: route.transcription
                    )
                    if let translation = route.translation {
                        routeLine(
                            "Translation",
                            decision: translation
                        )
                    }
                } else {
                    Label(
                        "Check the installed local models",
                        systemImage: "lock.shield"
                    )
                }
                Divider()
                Text(
                    routeDetail
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private func routeLine(
        _ title: String,
        decision: ModelRouteDecision
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            LabeledContent(title) {
                Label(
                    routeLabel(decision.route),
                    systemImage:
                        decision.route
                            == .approvedExternal
                        ? "network.badge.shield.half.filled"
                        : decision.route
                            == .appleOnDevice
                        ? "checkmark.shield.fill"
                        : "person.text.rectangle"
                )
                .foregroundStyle(
                    decision.route == .appleOnDevice
                        || decision.route
                            == .approvedExternal
                        ? .green
                        : .orange
                )
            }
            LabeledContent(
                "Execution boundary",
                value: decision.route.privacyRoute.encodedValue
            )
            LabeledContent(
                "Data categories",
                value:
                    decision.request.dataCategories
                    .map(\.rawValue)
                    .joined(separator: ", ")
            )
            LabeledContent(
                "Destination",
                value:
                    destinationLabel(
                        decision.request.destination
                    )
            )
            LabeledContent(
                "Retention",
                value:
                    decision.request.retentionPolicy.rawValue
            )
            LabeledContent(
                "Policy authority",
                value:
                    decision.request
                    .organizationAllowsExternalProcessing
                    ? "application router + organization allows external"
                    : "application router + organization local-only"
            )
            LabeledContent(
                "Visible user authorization",
                value:
                    decision.request.visibleUserAuthorization
                    ? "granted"
                    : "not granted"
            )
            LabeledContent(
                "No-outbound mode",
                value:
                    decision.request.securityPolicy?
                    .noOutboundMode == false
                    ? "disabled"
                    : "enforced"
            )
            if let policy = decision.request.securityPolicy {
                LabeledContent(
                    "Exact access-policy revision",
                    value:
                        String(
                            policy.accessPolicyRevision
                                .revisionID.canonicalString
                                .prefix(12)
                        ) + "…"
                )
            }
            LabeledContent(
                "Decision",
                value: decision.reasonCode
            )
        }
    }

    private func destinationLabel(
        _ destination: ModelDestinationPolicy
    ) -> String {
        switch destination {
        case .localDevice:
            "this Mac"
        case let .approvedProvider(identifier):
            "approved provider: \(identifier)"
        }
    }

    private func routeLabel(
        _ route: ModelExecutionRoute
    ) -> String {
        switch route {
        case .appleOnDevice:
            "Apple on-device model installed"
        case .approvedExternal:
            "Explicitly authorized remote STT"
        case .deterministicTest:
            "Deterministic test provider"
        case .manualFallback:
            "Record only / manual transcript"
        }
    }

    private var routeDetail: String {
        guard let route = store.routeReview else {
            return "Choose Local STT, a meeting-approved remote STT API, or Record only. Codex never receives audio."
        }
        if route.sendsAudioOffDevice {
            return route.isReady
                ? "The exact remote provider/model and policy revision are ready for this one authorized upload. No fallback is configured."
                : "The remote provider is selected, but upload authorization is not ready. No audio has been sent."
        }
        return route.selection == nil
            ? "STT is not configured. Recording and transcript import remain available; BlueMinutes will not claim that transcription is running."
            : "Meeting audio remains on this Mac. No provider fallback is configured."
    }

    private func transcriptJobCard(
        _ job: MediaJobReview
    ) -> some View {
        GroupBox("Transcript task") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent(
                    "State",
                    value:
                        job.state.rawValue
                        .replacingOccurrences(
                            of: "_",
                            with: " "
                        )
                )
                ProgressView(value: job.progressFraction)
                LabeledContent(
                    "Privacy",
                    value: job.privacyRoute.encodedValue
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

    private var manualFallbackCard: some View {
        GroupBox("Manual local fallback") {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    "Use this when an on-device model or language pair is unavailable. The text is labeled human-entered and receives complete timeline coverage; no provider is invoked."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                Text("Transcript")
                    .font(.headline)
                TextEditor(
                    text: $sceneState.manualTranscriptText
                )
                .frame(minHeight: 120)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator)
                }
                if !sceneState.transcriptTargetLanguageTag
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty
                {
                    Text("Translation")
                        .font(.headline)
                    TextEditor(
                        text:
                            $sceneState
                            .manualTranslationText
                    )
                    .frame(minHeight: 100)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.separator)
                    }
                }
                Toggle(
                    "I confirm this manual text accounts for the complete recording timeline",
                    isOn:
                        $sceneState
                        .manualCoverageConfirmed
                )
                Button("Publish Manual Transcript") {
                    Task {
                        await store.publishManualTranscript(
                            using: sceneState
                        )
                    }
                }
                .disabled(
                    store.isWorking
                        || !sceneState
                        .manualCoverageConfirmed
                )
            }
            .padding()
        }
    }

    private func reviewWorkspace(
        _ review: TranscriptReviewBundle
    ) -> some View {
        let cacheKey = TranscriptReviewPresentationCacheKey(
            review: review
        )
        let presentation: TranscriptReviewPresentation
        if let presentationCache,
           presentationCache.key == cacheKey
        {
            presentation = presentationCache.presentation
        } else {
            presentation = TranscriptReviewPresentation(
                review: review
            )
        }
        let selectedSegment = presentation.segment(
            id: sceneState.transcript.selectedSegmentID
        )
        let visibleSegments =
            presentation.segments(
                matching:
                    transcriptSearchQuery,
                scope:
                    transcriptOutlineScope
            )
        let selectedEvidence = selectedSegment.map {
            presentation.evidence(for: $0)
        } ?? []
        let selectedInspectorEvidenceRevisionID =
            TranscriptEvidenceInspectorSelection.resolve(
                requestedRevisionID:
                    inspectorEvidenceRevisionID,
                availableRevisionIDs:
                    selectedEvidence.map {
                        $0.revision.revisionID
                    }
            )
        let selectedCoverage = selectedSegment.map {
            presentation.coverage(for: $0)
        } ?? []
        let unresolvedEvidenceCount = selectedSegment.map {
            presentation.unresolvedEvidenceCount(for: $0)
        } ?? 0

        return VStack(spacing: 0) {
            reviewHeader(
                review: review,
                presentation: presentation,
                visibleSegmentCount:
                    visibleSegments.count
            )
            Divider()
            HSplitView {
                segmentList(
                    visibleSegments,
                    totalSegmentCount:
                        presentation.segments.count
                )
                    .frame(minWidth: 280, idealWidth: 340)
                segmentDetail(presentation)
                    .frame(minWidth: 420)
            }
        }
        .inspector(isPresented: inspectorPresentation) {
            EvidenceInspectorPanel(
                segment: selectedSegment,
                coverage: selectedCoverage,
                evidence: selectedEvidence,
                selectedEvidenceRevisionID:
                    selectedInspectorEvidenceRevisionID,
                unresolvedEvidenceCount:
                    unresolvedEvidenceCount,
                noSpeechChunks: presentation.noSpeechChunks
            )
            .inspectorColumnWidth(
                min: 280,
                ideal: 340,
                max: 460
            )
        }
        .focusedSceneValue(
            \.blueMinutesTranscriptCommandActions,
            commandActions(presentation)
        )
        .task(id: cacheKey) {
            guard presentationCache?.key != cacheKey else {
                return
            }
            presentationCache = TranscriptReviewPresentationCache(
                review: review
            )
        }
    }

    private func reviewHeader(
        review: TranscriptReviewBundle,
        presentation: TranscriptReviewPresentation,
        visibleSegmentCount: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                EvidenceBadge(
                    title: "100% deterministic core coverage",
                    systemImage: "checkmark.seal.fill"
                )
                EvidenceBadge(
                    title:
                        "\(presentation.uncertainSpeakerCount) uncertain speaker(s)",
                    systemImage:
                        "person.crop.circle.badge.questionmark"
                )
                if presentation.verifiedNoSpeechChunkCount > 0 {
                    EvidenceBadge(
                        title:
                            "\(presentation.verifiedNoSpeechChunkCount) verified no-speech chunk(s)",
                        systemImage: "waveform.slash"
                    )
                }
                if presentation.unresolvedNoSpeechChunkCount > 0 {
                    EvidenceBadge(
                        title:
                            "\(presentation.unresolvedNoSpeechChunkCount) unresolved no-speech proof(s)",
                        systemImage:
                            "exclamationmark.triangle"
                    )
                }
                Spacer()
                Button {
                    toggleInspector()
                } label: {
                    Label(
                        "Evidence Inspector",
                        systemImage:
                            "sidebar.trailing"
                    )
                }
                .accessibilityValue(
                    inspectorPresented
                        ? "Open"
                        : "Closed"
                )
            }

            HStack {
                Button("Previous Segment") {
                    requestPrevious(presentation)
                }
                .disabled(
                    !canNavigate(
                        to: presentation.navigation.previous(
                            to:
                                sceneState.transcript
                                .selectedSegmentID
                        )
                    )
                )
                Button("Next Segment") {
                    requestNext(presentation)
                }
                .disabled(
                    !canNavigate(
                        to: presentation.navigation.next(
                            to:
                                sceneState.transcript
                                .selectedSegmentID
                        )
                    )
                )
                Button("Save Focused Draft") {
                    saveFocusedDraft()
                }
                .disabled(!canSaveFocusedDraft)
                Spacer()
                LabeledContent(
                    "Segments",
                    value: String(presentation.segments.count)
                )
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(
                    "Search transcript",
                    text:
                        $transcriptSearchQuery
                )
                .textFieldStyle(.roundedBorder)
                .frame(
                    minWidth: 180,
                    idealWidth: 280,
                    maxWidth: 360
                )
                .accessibilityIdentifier(
                    "BlueMinutes.Transcript.Search"
                )
                Picker(
                    "Filter",
                    selection:
                        $transcriptOutlineScope
                ) {
                    ForEach(
                        TranscriptOutlineScope
                            .allCases
                    ) { scope in
                        Text(scope.label)
                            .tag(scope)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier(
                    "BlueMinutes.Transcript.OutlineFilter"
                )
                Menu {
                    ForEach(
                        presentation.outlineAnchors
                    ) { anchor in
                        Button(anchor.label) {
                            guard canNavigate(
                                to: anchor
                                    .segmentID
                            ) else {
                                return
                            }
                            sceneState
                                .requestTranscriptSelection(
                                    anchor
                                    .segmentID
                                )
                        }
                    }
                } label: {
                    Label(
                        "Time Outline",
                        systemImage:
                            "list.bullet.indent"
                    )
                }
                .disabled(
                    presentation
                        .outlineAnchors.isEmpty
                )
                .accessibilityIdentifier(
                    "BlueMinutes.Transcript.TimeOutline"
                )
                if !transcriptSearchQuery.isEmpty {
                    Button {
                        transcriptSearchQuery =
                            ""
                    } label: {
                        Label(
                            "Clear Search",
                            systemImage:
                                "xmark.circle.fill"
                        )
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel(
                        "Clear transcript search"
                    )
                }
                Spacer()
                Text(
                    "\(visibleSegmentCount) shown"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if transcriptSearchQuery.utf8.count
                > TranscriptReviewPresentation
                .maximumSearchQueryUTF8Bytes
            {
                Label(
                    "Search text is limited to \(TranscriptReviewPresentation.maximumSearchQueryUTF8Bytes) UTF-8 bytes.",
                    systemImage:
                        "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(
                    BlueMinutesColors.error
                )
            }

            DisclosureGroup(
                "Coverage and route proof"
            ) {
                Grid(
                    alignment: .leading,
                    horizontalSpacing: 18,
                    verticalSpacing: 7
                ) {
                    GridRow {
                        Text("Manifest")
                        Text(
                            shortRevision(
                                review.manifest.manifestID
                                    .canonicalString
                            )
                        )
                    }
                    GridRow {
                        Text("Status")
                        Text(
                            review.manifest.status.rawValue
                                .capitalized
                        )
                    }
                    GridRow {
                        Text("Core chunks")
                        Text(
                            String(
                                review.manifest.chunks.count
                            )
                        )
                    }
                    GridRow {
                        Text("No-speech proof")
                        Text(
                            "\(presentation.verifiedNoSpeechChunkCount) exact digital silence; \(presentation.unresolvedNoSpeechChunkCount) unresolved"
                        )
                    }
                    GridRow {
                        Text("Transcription route")
                        Text(
                            label(
                                review.manifest
                                    .transcriptionRoute
                                    .route.rawValue
                            )
                        )
                    }
                    GridRow {
                        Text("Privacy boundary")
                        Text(
                            label(
                                review.manifest
                                    .transcriptionRoute
                                    .route.privacyRoute
                                    .encodedValue
                            )
                        )
                    }
                    GridRow {
                        Text("Canonical source")
                        Text(
                            shortRevision(
                                review.manifest
                                    .canonicalSourceRevision
                                    .revisionID
                                    .canonicalString
                            )
                        )
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func segmentList(
        _ segments: [TranscriptSegmentV1],
        totalSegmentCount: Int
    ) -> some View {
        Group {
            if segments.isEmpty {
                ContentUnavailableView(
                    "No Matching Segments",
                    systemImage:
                        "text.magnifyingglass",
                    description: Text(
                        totalSegmentCount == 0
                            ? "This published transcript contains no speech segments."
                            : "Change the transcript search or outline filter."
                    )
                )
            } else {
                List(
                    segments,
                    id: \.segmentID,
                    selection:
                        transcriptSelection
                ) { segment in
                    VStack(
                        alignment: .leading,
                        spacing: 5
                    ) {
                        Text(segment.text)
                            .lineLimit(2)
                        HStack {
                            Text(
                                timeLabel(
                                    segment
                                        .timeRange
                                )
                            )
                            Text(
                                label(
                                    segment
                                        .reviewStatus
                                        .encodedValue
                                )
                            )
                            Spacer()
                            Text(
                                provenanceLabel(
                                    segment
                                        .revision
                                        .createdBy
                                )
                            )
                        }
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }
                    .tag(segment.segmentID)
                    .accessibilityElement(
                        children: .combine
                    )
                    .accessibilityLabel(
                        "\(timeLabel(segment.timeRange)), \(segment.text)"
                    )
                    .accessibilityValue(
                        "\(provenanceLabel(segment.revision.createdBy)), \(label(segment.reviewStatus.encodedValue))"
                    )
                }
                .listStyle(.inset)
                .accessibilityIdentifier(
                    "BlueMinutes.Transcript.SearchResults"
                )
            }
        }
    }

    @ViewBuilder
    private func segmentDetail(
        _ presentation: TranscriptReviewPresentation
    ) -> some View {
        if let segment = presentation.segment(
            id: sceneState.transcript.selectedSegmentID
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    sourceTranscriptSection(
                        segment,
                        presentation: presentation
                    )
                    if let translation =
                        presentation.translation(
                            for: segment
                        )
                    {
                        translationSection(
                            targetLabel:
                                translation.targetLanguage
                                .value,
                            sourceRevisionIsCurrent: true
                        )
                    } else if sceneState.transcript
                        .translationIsDirty
                    {
                        translationSection(
                            targetLabel:
                                "retained prior translation",
                            sourceRevisionIsCurrent: false
                        )
                    }
                    speakerSection(
                        segment,
                        presentation: presentation
                    )
                }
                .padding(20)
            }
        } else {
            ContentUnavailableView(
                "Select a Transcript Segment",
                systemImage: "text.bubble",
                description: Text(
                    "Review source text, separate translations, uncertain speakers, and exact evidence."
                )
            )
        }
    }

    private func sourceTranscriptSection(
        _ segment: TranscriptSegmentV1,
        presentation: TranscriptReviewPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorialSectionHeader(
                "Source transcript revision",
                detail:
                    "Machine transcription, human correction, confidence, and confirmation remain separate claims."
            )
            HStack {
                EvidenceBadge(
                    title:
                        provenanceLabel(
                            segment.revision.createdBy
                        ),
                    systemImage:
                        provenanceIcon(
                            segment.revision.createdBy
                        )
                )
                EvidenceBadge(
                    title:
                        "Confidence \(confidenceLabel(segment.confidence))",
                    systemImage: "chart.bar"
                )
                EvidenceBadge(
                    title:
                        segment.userConfirmed
                        ? "Human confirmed"
                        : "Not human confirmed",
                    systemImage:
                        segment.userConfirmed
                        ? "person.crop.circle.badge.checkmark"
                        : "person.crop.circle.badge.questionmark"
                )
            }
            LabeledContent(
                "Time",
                value: timeLabel(segment.timeRange)
            )
            LabeledContent(
                "Language",
                value: segment.detectedLanguage.value
            )
            LabeledContent(
                "Speech source",
                value: label(
                    segment.speechSourceKind.encodedValue
                )
            )
            LabeledContent(
                "Revision",
                value:
                    shortRevision(
                        segment.revision.revisionID
                            .canonicalString
                    )
            )

            DisclosureGroup("Revision lineage") {
                VStack(
                    alignment: .leading,
                    spacing: 7
                ) {
                    LabeledContent(
                        "Exact source asset",
                        value:
                            shortRevision(
                                segment
                                    .sourceAssetRevision
                                    .revisionID
                                    .canonicalString
                            )
                    )
                    LabeledContent(
                        "Created by",
                        value:
                            label(
                                segment.revision
                                    .createdBy
                                    .encodedValue
                            )
                    )
                    LabeledContent(
                        "Inputs",
                        value:
                            String(
                                segment.revision
                                    .inputRevisions.count
                            )
                    )
                    if let superseded =
                        segment.revision
                        .supersedesRevisionID
                    {
                        LabeledContent(
                            "Supersedes",
                            value:
                                shortRevision(
                                    superseded
                                        .canonicalString
                                )
                        )
                    }
                    if let provider =
                        segment.transcriptionProvider
                    {
                        LabeledContent(
                            "Provider",
                            value:
                                provider
                                .providerIdentifier
                        )
                        LabeledContent(
                            "Model",
                            value:
                                provider.modelIdentifier
                        )
                    }
                }
                .padding(.top, 6)
            }

            transcriptDraftState

            TextEditor(
                text:
                    $sceneState.transcript
                    .transcriptText
            )
            .focused(
                $focusedEditor,
                equals: .transcript
            )
            .frame(minHeight: 140)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.separator)
            }

            HStack {
                Button("Save Transcript Correction") {
                    saveDraft(.transcript)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    store.isWorking
                        || !sceneState.transcript
                        .transcriptIsDirty
                )
                if sceneState.transcript
                    .transcriptIsDirty
                {
                    Button("Revert Transcript Draft") {
                        sceneState.transcript
                            .discardTranscriptChanges()
                    }
                }
            }

            let evidence = presentation.evidence(
                for: segment
            )
            if !evidence.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Evidence anchors")
                        .font(.caption.weight(.semibold))
                    ForEach(
                        evidence,
                        id: \.revision.revisionID
                    ) { item in
                        EvidenceAnchor(
                            evidence: item
                        ) {
                            inspectorEvidenceRevisionID =
                                item.revision.revisionID
                            presentInspector()
                        }
                    }
                }
            }
            let unresolved =
                presentation.unresolvedEvidenceCount(
                    for: segment
                )
            if unresolved > 0 {
                WorkflowStateView(
                    title:
                        "Evidence resolution failed closed",
                    detail:
                        "\(unresolved) referenced evidence revision(s) are unavailable and are not represented as evidence.",
                    systemImage:
                        "exclamationmark.triangle",
                    tone: .failure
                )
            }
        }
    }

    private var transcriptDraftState: some View {
        Group {
            if sceneState.transcript.transcriptIsDirty {
                WorkflowStateView(
                    title: "Unsaved local draft",
                    detail:
                        "This correction has not created a replacement TranscriptSegment revision.",
                    systemImage: "pencil.circle",
                    tone: .warning
                )
            } else {
                WorkflowStateView(
                    title: "Saved",
                    detail:
                        "The editor matches the active published TranscriptSegment revision.",
                    systemImage: "checkmark.circle",
                    tone: .success
                )
            }
        }
        .accessibilityIdentifier(
            "BlueMinutes.Transcript.DraftState"
        )
    }

    private func translationSection(
        targetLabel: String,
        sourceRevisionIsCurrent: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorialSectionHeader(
                "Separate translation revision",
                detail:
                    "Translation remains a separate object bound to one exact TranscriptSegment revision."
            )
            LabeledContent(
                "Target",
                value: targetLabel
            )
            if !sourceRevisionIsCurrent {
                WorkflowStateView(
                    title:
                        "Source revision changed",
                    detail:
                        "The draft is retained. An incompatible save fails closed without discarding it.",
                    systemImage:
                        "exclamationmark.triangle.fill",
                    tone: .warning
                )
            }
            if sceneState.transcript.translationIsDirty {
                WorkflowStateView(
                    title:
                        "Unsaved translation draft",
                    detail:
                        "This text has not created a replacement TranslationSegment revision.",
                    systemImage: "pencil.circle",
                    tone: .warning
                )
            } else {
                WorkflowStateView(
                    title: "Saved translation",
                    detail:
                        "The editor matches the active TranslationSegment revision.",
                    systemImage: "checkmark.circle",
                    tone: .success
                )
            }
            TextEditor(
                text:
                    $sceneState.transcript
                    .translationText
            )
            .focused(
                $focusedEditor,
                equals: .translation
            )
            .frame(minHeight: 120)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.separator)
            }
            HStack {
                Button("Save Translation Correction") {
                    saveDraft(.translation)
                }
                .disabled(
                    store.isWorking
                        || !sceneState.transcript
                        .translationIsDirty
                )
                if sceneState.transcript
                    .translationIsDirty
                {
                    Button("Revert Translation Draft") {
                        sceneState.transcript
                            .discardTranslationChanges()
                    }
                }
            }
        }
    }

    private func speakerSection(
        _ segment: TranscriptSegmentV1,
        presentation: TranscriptReviewPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorialSectionHeader(
                "Speaker review",
                detail:
                    "Speaker confirmation remains distinct from transcript confidence and requires exact evidence."
            )
            if presentation.hasConfirmedSpeaker(
                for: segment
            ) {
                WorkflowStateView(
                    title:
                        "Speaker assignment confirmed",
                    detail:
                        "A current human-confirmed SpeakerAssignment revision covers this exact TranscriptSegment revision.",
                    systemImage:
                        "person.crop.circle.badge.checkmark",
                    tone: .success
                )
            } else {
                WorkflowStateView(
                    title:
                        "Uncertain speaker — confirmation required",
                    detail:
                        "Enter a reviewed display name. Saving creates the existing evidence-linked confirmation objects.",
                    systemImage:
                        "person.crop.circle.badge.questionmark",
                    tone: .warning
                )
                TextField(
                    "Speaker name",
                    text:
                        $sceneState.transcript
                        .speakerName
                )
                .focused(
                    $focusedEditor,
                    equals: .speaker
                )
                if sceneState.transcript.speakerIsDirty {
                    WorkflowStateView(
                        title:
                            "Unsaved speaker draft",
                        detail:
                            "No SpeakerAssignment revision has been created for this name.",
                        systemImage: "pencil.circle",
                        tone: .warning
                    )
                }
                HStack {
                    Button("Confirm Speaker") {
                        saveDraft(.speaker)
                    }
                    .disabled(
                        store.isWorking
                            || !sceneState.transcript
                            .speakerIsDirty
                    )
                    if sceneState.transcript
                        .speakerIsDirty
                    {
                        Button("Clear Speaker Draft") {
                            sceneState.transcript
                                .discardSpeakerChanges()
                        }
                    }
                }
            }
        }
    }

    private func commandActions(
        _ presentation: TranscriptReviewPresentation
    ) -> BlueMinutesTranscriptCommandActions {
        let selectedID =
            sceneState.transcript.selectedSegmentID
        let previousID = presentation.navigation.previous(
            to: selectedID
        )
        let nextID = presentation.navigation.next(
            to: selectedID
        )
        return BlueMinutesTranscriptCommandActions(
            canSelectPrevious:
                canNavigate(to: previousID),
            canSelectNext:
                canNavigate(to: nextID),
            canSaveFocusedDraft:
                canSaveFocusedDraft,
            selectPrevious: {
                guard canNavigate(to: previousID),
                      let previousID
                else { return }
                sceneState.requestTranscriptSelection(
                    previousID
                )
            },
            selectNext: {
                guard canNavigate(to: nextID),
                      let nextID
                else { return }
                sceneState.requestTranscriptSelection(
                    nextID
                )
            },
            saveFocusedDraft: {
                saveFocusedDraft()
            },
            toggleInspector: {
                toggleInspector()
            }
        )
    }

    private var savableDraftKind: TranscriptDraftKind? {
        TranscriptDraftSaveResolution.resolve(
            focusedEditor: focusedEditor,
            transcriptIsDirty:
                sceneState.transcript.transcriptIsDirty,
            translationIsDirty:
                sceneState.transcript.translationIsDirty,
            speakerIsDirty:
                sceneState.transcript.speakerIsDirty
        )
    }

    private func canNavigate(
        to destination: TranscriptSegmentID?
    ) -> Bool {
        TranscriptCommandAvailability.canNavigate(
            hasDestination: destination != nil,
            isWorking: store.isWorking,
            isInteractionLocked:
                sceneState.isInteractionLocked,
            isConfirmationPresented:
                sceneState.isNavigationConfirmationPresented
        )
    }

    private var canSaveFocusedDraft: Bool {
        TranscriptCommandAvailability.canSave(
            hasSavableDraft: savableDraftKind != nil,
            isWorking: store.isWorking,
            isInteractionLocked:
                sceneState.isInteractionLocked,
            isConfirmationPresented:
                sceneState.isNavigationConfirmationPresented
        )
    }

    private func requestPrevious(
        _ presentation: TranscriptReviewPresentation
    ) {
        guard
            let previousID = presentation.navigation.previous(
                to:
                    sceneState.transcript
                    .selectedSegmentID
            ),
            canNavigate(to: previousID)
        else { return }
        sceneState.requestTranscriptSelection(previousID)
    }

    private func requestNext(
        _ presentation: TranscriptReviewPresentation
    ) {
        guard
            let nextID = presentation.navigation.next(
                to:
                    sceneState.transcript
                    .selectedSegmentID
            ),
            canNavigate(to: nextID)
        else { return }
        sceneState.requestTranscriptSelection(nextID)
    }

    private func saveFocusedDraft() {
        guard canSaveFocusedDraft,
              let savableDraftKind
        else { return }
        saveDraft(savableDraftKind)
    }

    private func saveDraft(_ kind: TranscriptDraftKind) {
        let operation: MediaReviewEditorSaveOperation?
        switch kind {
        case .transcript:
            operation =
                sceneState.beginDirectTranscriptSave()
        case .translation:
            operation =
                sceneState.beginDirectTranslationSave()
        case .speaker:
            operation =
                sceneState.beginDirectSpeakerSave()
        }
        guard let operation else { return }

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
                sceneState.transcript.reconcile(
                    with: store.transcriptReview
                )
            }
        }
    }

    private var transcriptSelection:
        Binding<TranscriptSegmentID?>
    {
        Binding(
            get: {
                sceneState.transcript.selectedSegmentID
            },
            set: {
                sceneState.requestTranscriptSelection($0)
            }
        )
    }

    private func timeLabel(
        _ range: MediaTimeRange
    ) -> String {
        let start =
            Double(range.startMilliseconds) / 1_000
        let end =
            Double(range.endMilliseconds) / 1_000
        return
            "\(start.formatted(.number.precision(.fractionLength(1))))–\(end.formatted(.number.precision(.fractionLength(1)))) s"
    }

    private func confidenceLabel(
        _ confidence: ConfidenceScore
    ) -> String {
        let percent =
            Double(confidence.millionths) / 10_000
        return percent.formatted(
            .number.precision(.fractionLength(1))
        ) + "%"
    }

    private func provenanceLabel(
        _ actor: CreationActor
    ) -> String {
        switch actor {
        case .provider:
            "Machine transcription"
        case .user:
            "Human correction"
        case .application:
            "Application-authored"
        case .importProcess:
            "Imported transcript"
        case let .unrecognized(value):
            label(value)
        }
    }

    private func provenanceIcon(
        _ actor: CreationActor
    ) -> String {
        switch actor {
        case .provider:
            "cpu"
        case .user:
            "person.crop.circle"
        case .application:
            "app.badge"
        case .importProcess:
            "square.and.arrow.down"
        case .unrecognized:
            "questionmark.circle"
        }
    }

    private func shortRevision(
        _ canonicalString: String
    ) -> String {
        String(canonicalString.prefix(12)) + "…"
    }

    private func label(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

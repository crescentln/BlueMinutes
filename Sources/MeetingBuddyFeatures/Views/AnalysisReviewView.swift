import MeetingBuddyApplication
import MeetingBuddyDomain
import Observation
import SwiftUI

struct AnalysisReviewView: View {
    @Bindable var store: MediaReviewStore
    @Bindable var sceneState: MediaReviewSceneState
    @State private var inspectorIsPresented = false
    @State private var evidenceSelection:
        AnalysisEvidenceSelection?
    @State private var presentationCache:
        AnalysisReviewPresentationCache?

    init(
        store: MediaReviewStore,
        sceneState:
            MediaReviewSceneState,
        initialInspectorIsPresented:
            Bool = false,
        initialEvidenceSelection:
            AnalysisEvidenceSelection? = nil
    ) {
        self.store = store
        self.sceneState = sceneState
        _inspectorIsPresented =
            State(
                initialValue:
                    initialInspectorIsPresented
            )
        _evidenceSelection =
            State(
                initialValue:
                    initialEvidenceSelection
            )
    }

    var body: some View {
        Group {
            if let review = store.analysisReview {
                reviewWorkspace(review)
            } else {
                setupView
            }
        }
        .onAppear {
            sceneState.analysis.reconcile(with: store.analysisReview)
        }
        .onChange(of: sceneState.analysis.selectedPositionID) { _, _ in
            sceneState.analysis.reconcile(with: store.analysisReview)
        }
        .onChange(of: store.analysisReview?.ledger.ledgerID) { _, _ in
            sceneState.analysis.reconcile(with: store.analysisReview)
            evidenceSelection = nil
            inspectorIsPresented = false
        }
        .onChange(of: store.analysisReview?.positions.map(\.revision.revisionID)) { _, _ in
            sceneState.analysis.reconcile(with: store.analysisReview)
            evidenceSelection = nil
            inspectorIsPresented = false
        }
    }

    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                routeCard
                if let job = store.analysisJob {
                    jobCard(job)
                }
                GroupBox("Create evidence-linked intelligence") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Analyze Locally is explicit authorization for one bounded on-device run. The Apple model receives one reviewed segment at a time; deterministic validation and complete coverage must pass before publication.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Check Local Analysis Model") {
                                Task { await store.refreshAnalysisRoute() }
                            }
                            Button("Analyze Locally") {
                                Task { await store.startAnalysis(using: sceneState) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                store.analysisRouteReview?.isOnDeviceReady != true
                                    || store.isWorking
                            )
                        }
                        if store.analysisRouteReview?.isOnDeviceReady == false {
                            Label(
                                "No automatic route is available. No meeting content will be sent elsewhere; previously published local cards remain reviewable.",
                                systemImage: "lock.shield"
                            )
                            .foregroundStyle(.orange)
                        }
                    }
                    .padding()
                }
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    private var routeCard: some View {
        GroupBox("Analysis privacy route") {
            VStack(alignment: .leading, spacing: 9) {
                if let review = store.analysisRouteReview {
                    let decision = review.analysis
                    LabeledContent(
                        "Route",
                        value: decision.route == .appleOnDevice
                            ? "Apple Foundation Models on device"
                            : "No automatic local model"
                    )
                    LabeledContent("Destination", value: "this Mac")
                    LabeledContent("Provider retention", value: decision.request.retentionPolicy.rawValue)
                    LabeledContent(
                        "Data categories",
                        value: decision.request.dataCategories.map(\.rawValue).joined(separator: ", ")
                    )
                    LabeledContent("Policy decision", value: decision.reasonCode)
                    LabeledContent(
                        "No-outbound mode",
                        value: decision.request.securityPolicy?.noOutboundMode == false
                            ? "disabled" : "enforced"
                    )
                    LabeledContent(
                        "Runtime",
                        value: "\(review.runtimeEvidence.operatingSystemVersion) · \(review.runtimeEvidence.adapterVersion)"
                    )
                    LabeledContent(
                        "Model available",
                        value: review.runtimeEvidence.modelAvailable ? "yes" : "no"
                    )
                } else {
                    Label("Check the local model after reviewing speakers", systemImage: "lock.shield")
                }
                Divider()
                Text("Task 006A adds no cloud adapter, network tool, credential, model download, or external retention path. Published derived objects are stored only in the selected local workspace.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private func jobCard(_ job: MediaJobReview) -> some View {
        GroupBox("Local analysis task") {
            VStack(alignment: .leading, spacing: 9) {
                LabeledContent("State", value: job.state.rawValue.replacingOccurrences(of: "_", with: " "))
                ProgressView(value: job.progressFraction)
                LabeledContent(
                    "Coverage progress",
                    value: "\(job.completedUnitCount) / \(job.totalUnitCount) segments"
                )
                if let failure = job.safeFailureSummary {
                    Text(failure).foregroundStyle(.red)
                }
            }
            .padding()
        }
    }

    private func reviewWorkspace(_ review: AnalysisReviewBundle) -> some View {
        let cacheKey = AnalysisReviewPresentationCacheKey(
            review: review
        )
        let presentation: AnalysisReviewPresentation
        if let presentationCache,
           presentationCache.key == cacheKey
        {
            presentation = presentationCache.presentation
        } else {
            presentation = AnalysisReviewPresentation(
                review: review
            )
        }
        let selectedEvidence = evidenceSelection.flatMap {
            presentation.evidence(
                for: $0.evidenceReference
            )
        }

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                EditorialSectionHeader(
                    "Analysis Review",
                    detail:
                        "Inspect exact evidence, confidence, provenance, and whole-ledger confirmation before publishing a correction."
                )
                analysisConfirmationCard(review)
                coverageHeader(review)
                delegationCards(
                    review,
                    presentation: presentation
                )
                interventionCards(
                    review,
                    presentation: presentation
                )
                positionEditor(
                    review,
                    presentation: presentation
                )
            }
            .padding(24)
            .frame(maxWidth: 1_020, alignment: .leading)
        }
        .inspector(isPresented: $inspectorIsPresented) {
            AnalysisEvidenceInspectorPanel(
                selection: evidenceSelection,
                evidence: selectedEvidence,
                ledgerIsHumanConfirmed: review.isHumanConfirmed
            )
            .inspectorColumnWidth(
                min: 300,
                ideal: 360,
                max: 480
            )
        }
        .task(id: cacheKey) {
            guard presentationCache?.key != cacheKey else {
                return
            }
            if presentationCache != nil {
                evidenceSelection = nil
                inspectorIsPresented = false
            }
            presentationCache = AnalysisReviewPresentationCache(
                review: review
            )
        }
    }

    private func analysisConfirmationCard(_ review: AnalysisReviewBundle) -> some View {
        GroupBox("Analysis review boundary") {
            VStack(alignment: .leading, spacing: 10) {
                if review.isHumanConfirmed {
                    Label(
                        "Every claim in this exact analysis ledger was explicitly confirmed by the user.",
                        systemImage: "person.crop.circle.badge.checkmark"
                    )
                    .foregroundStyle(.green)
                } else {
                    Label(
                        "Quarantined model candidate — not approved for briefing generation, position correction, history, or export.",
                        systemImage: "exclamationmark.shield.fill"
                    )
                    .foregroundStyle(.orange)
                    Toggle(
                        "I reviewed every claim, qualification, speaker identity, and evidence link in this analysis.",
                        isOn: $sceneState.analysisClaimsConfirmed
                    )
                    Button("Confirm Exact Analysis Ledger") {
                        Task { await store.confirmAnalysisReview(using: sceneState) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!sceneState.analysisClaimsConfirmed || store.isWorking)
                }
            }
            .padding()
        }
    }

    private func coverageHeader(_ review: AnalysisReviewBundle) -> some View {
        GroupBox("Analysis coverage proof") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    Text("Coverage")
                    Label(
                        "\(review.ledger.segments.count) / \(review.ledger.eligibleSegmentRevisions.count) eligible segments",
                        systemImage: "checkmark.seal.fill"
                    )
                    .foregroundStyle(.green)
                }
                GridRow {
                    Text("Substantive")
                    Text(String(review.ledger.segments.filter { $0.disposition == .substantive }.count))
                }
                GridRow {
                    Text("Non-substantive")
                    Text(String(review.ledger.segments.filter { $0.disposition == .nonSubstantive }.count))
                }
                GridRow { Text("Route"); Text(review.ledger.analysisRoute.route.rawValue) }
                GridRow {
                    Text("Human confirmation")
                    Text(review.isHumanConfirmed ? "confirmed" : "quarantined candidate")
                }
                GridRow { Text("Prompt modules"); Text(review.ledger.promptModules.map { "\($0.identifier)@\($0.version)" }.joined(separator: ", ")) }
                GridRow { Text("Input digest"); Text(short(review.ledger.inputPackageDigest.lowercaseHex)).monospaced() }
                GridRow { Text("Ledger revision"); Text(short(review.ledger.ledgerID.canonicalString)).monospaced() }
            }
            .padding()
        }
    }

    private func delegationCards(
        _ review: AnalysisReviewBundle,
        presentation: AnalysisReviewPresentation
    ) -> some View {
        GroupBox("Delegation-position cards") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(review.delegationPositionCards, id: \.revision.revisionID) { card in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(
                                representedName(
                                    card.representedEntityRevision,
                                    presentation: presentation
                                )
                            )
                                .font(.headline)
                            Text(
                                "· "
                                    + issueName(
                                        card.issueRevision,
                                        presentation: presentation
                                    )
                            )
                                .foregroundStyle(.secondary)
                            Spacer()
                            if presentation.isStale(card) {
                                Label("Stale after correction", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            } else {
                                Text(card.reviewStatus.encodedValue)
                                .foregroundStyle(.secondary)
                            }
                        }
                        claimView(
                            "Overall position",
                            claim: card.overallPosition,
                            presentation: presentation
                        )
                        claimsView(
                            "Reservations",
                            claims: card.reservations,
                            presentation: presentation
                        )
                        claimsView(
                            "Conditions",
                            claims: card.conditions,
                            presentation: presentation
                        )
                        LabeledContent(
                            "Exact inputs",
                            value: "\(card.positionRevisions.count) position · \(card.speakingCapacityRevisions.count) capacity revisions"
                        )
                        .font(.caption)
                        LabeledContent(
                            "Candidate provenance",
                            value: label(
                                card.revision.createdBy
                                    .encodedValue
                            )
                        )
                        .font(.caption)
                    }
                    if card.revision.revisionID != review.delegationPositionCards.last?.revision.revisionID {
                        Divider()
                    }
                }
            }
            .padding()
        }
    }

    private func interventionCards(
        _ review: AnalysisReviewBundle,
        presentation: AnalysisReviewPresentation
    ) -> some View {
        GroupBox("Intervention cards") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(review.interventionCards, id: \.revision.revisionID) { card in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(card.interventionType.encodedValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.headline)
                            Text("\(time(card.timeRange.startMilliseconds))–\(time(card.timeRange.endMilliseconds))")
                                .foregroundStyle(.secondary)
                        }
                        claimView(
                            "Summary",
                            claim: card.shortSummary,
                            presentation: presentation
                        )
                        claimsView(
                            "Notable wording",
                            claims: card.notableWording,
                            presentation: presentation
                        )
                        LabeledContent(
                            "Typed objects",
                            value: "\(card.positionRevisions.count) position · \(card.commitmentRevisions.count) commitment · \(card.decisionRevisions.count) decision"
                        )
                        .font(.caption)
                        LabeledContent(
                            "Candidate provenance",
                            value: label(
                                card.revision.createdBy
                                    .encodedValue
                            )
                        )
                        .font(.caption)
                    }
                }
            }
            .padding()
        }
    }

    private func positionEditor(
        _ review: AnalysisReviewBundle,
        presentation: AnalysisReviewPresentation
    ) -> some View {
        GroupBox("Inspect and correct positions") {
            HSplitView {
                List(
                    presentation.positions,
                    id: \.revision.revisionID,
                    selection: positionSelection
                ) { position in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(position.statement.text).lineLimit(2)
                        Text("\(position.positionType.encodedValue) · \(position.reviewStatus.encodedValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(position.positionID)
                }
                .frame(minWidth: 260, idealWidth: 320, minHeight: 360)

                if let position = presentation.position(
                    id: sceneState.analysis.selectedPositionID
                ) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            EditorialSectionHeader(
                                "Position Dossier",
                                detail:
                                    "The published revision remains immutable. Saving creates one exact user-confirmed successor."
                            )
                            LabeledContent("Actor revision", value: short(position.actorRevision.logicalID.canonicalString))
                            LabeledContent(
                                "Represented entity",
                                value: representedName(
                                    position
                                        .representedEntityRevision,
                                    presentation: presentation
                                )
                            )
                            LabeledContent("Speaking capacity revision", value: short(position.speakingCapacityRevision.revisionID.canonicalString))
                            LabeledContent(
                                "Issue",
                                value: issueName(
                                    position.issueRevision,
                                    presentation: presentation
                                )
                            )
                            LabeledContent("Claim taxonomy", value: position.statement.taxonomy.encodedValue)
                            LabeledContent("Evidence support", value: position.statement.supportStatus.encodedValue)
                            LabeledContent(
                                "Claim confidence",
                                value: confidenceLabel(
                                    position.statement.confidence
                                )
                            )
                            LabeledContent(
                                "Candidate provenance",
                                value: label(
                                    position.revision.createdBy
                                        .encodedValue
                                )
                            )
                            LabeledContent(
                                "Whole-ledger human confirmation",
                                value: review.isHumanConfirmed
                                    ? "confirmed"
                                    : "not confirmed"
                            )
                            LabeledContent("Evidence revisions", value: String(position.statement.evidenceRevisions.count))
                            LabeledContent("Comparison state", value: position.comparisonState.encodedValue)
                            LabeledContent("Revision", value: short(position.revision.revisionID.canonicalString))
                                .monospaced()
                            evidenceAnchors(
                                context: "Position statement",
                                claim: position.statement,
                                presentation: presentation
                            )
                            claimsView(
                                "Published reservations",
                                claims: position.reservations,
                                presentation: presentation
                            )
                            claimsView(
                                "Published conditions",
                                claims: position.conditions,
                                presentation: presentation
                            )
                            if !sceneState.analysis
                                .isSourceRevisionCurrent
                            {
                                WorkflowStateView(
                                    title:
                                        "Draft source revision changed",
                                    detail:
                                        "This draft is based on an earlier Position revision. Keep or copy the text, then review the current revision before saving.",
                                    systemImage:
                                        "exclamationmark.triangle",
                                    tone: .failure
                                )
                            } else if sceneState.analysis.isDirty {
                                WorkflowStateView(
                                    title: "Unpublished correction draft",
                                    detail:
                                        "Saving will create one immutable user-confirmed Position revision.",
                                    systemImage:
                                        "square.and.pencil",
                                    tone: .warning
                                )
                            } else {
                                WorkflowStateView(
                                    title: "Published revision loaded",
                                    detail:
                                        "Edit a field before creating a successor revision.",
                                    systemImage:
                                        "checkmark.circle",
                                    tone: .success
                                )
                            }
                            Picker(
                                "Position type",
                                selection: $sceneState.analysis.positionType
                            ) {
                                ForEach(PositionChoice.all) { choice in
                                    Text(choice.label).tag(choice.value)
                                }
                            }
                            Text("Statement").font(.headline)
                            TextEditor(text: $sceneState.analysis.statement)
                                .frame(minHeight: 110)
                                .overlay { RoundedRectangle(cornerRadius: 6).stroke(.separator) }
                            Text("Reservations — one per line").font(.headline)
                            TextEditor(text: $sceneState.analysis.reservations)
                                .frame(minHeight: 70)
                                .overlay { RoundedRectangle(cornerRadius: 6).stroke(.separator) }
                            Text("Conditions — one per line").font(.headline)
                            TextEditor(text: $sceneState.analysis.conditions)
                                .frame(minHeight: 70)
                                .overlay { RoundedRectangle(cornerRadius: 6).stroke(.separator) }
                            Text("Saving creates an immutable user-confirmed Position revision. Dependent cards remain in history and are marked stale; they are not silently rewritten.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Save Confirmed Position Revision") {
                                guard let operation =
                                    sceneState.beginDirectAnalysisSave()
                                else { return }
                                Task {
                                    let succeeded = await store.saveEditorDraft(
                                        operation.request
                                    )
                                    if sceneState.completeDirectEditorSave(
                                        operation,
                                        succeeded: succeeded,
                                        updatedReviews: store.editorReviewSnapshot
                                    ) {
                                        sceneState.analysis.reconcile(
                                            with: store.analysisReview
                                        )
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                store.isWorking
                                    || !review.isHumanConfirmed
                                    || !sceneState.analysis
                                        .isDirty
                                    || !sceneState.analysis
                                        .isSourceRevisionCurrent
                                    || sceneState
                                        .isInteractionLocked
                                    || sceneState
                                        .isNavigationConfirmationPresented
                                    || sceneState.analysis.statement
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                        .isEmpty
                            )
                        }
                        .padding()
                    }
                    .frame(minWidth: 420, minHeight: 360)
                } else {
                    ContentUnavailableView(
                        "Select a Position",
                        systemImage: "text.quote",
                        description: Text("Inspect evidence, qualifications, identity, and revision state.")
                    )
                    .frame(minWidth: 420, minHeight: 360)
                }
            }
            .padding()
        }
    }

    private func claimView(
        _ title: String,
        claim: EvidenceLinkedClaim,
        presentation: AnalysisReviewPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(claim.text)
            HStack(spacing: 8) {
                EvidenceBadge(
                    title: label(claim.taxonomy.encodedValue),
                    systemImage: "quote.bubble"
                )
                EvidenceBadge(
                    title:
                        "\(label(claim.supportStatus.encodedValue)) support",
                    systemImage: "checkmark.shield"
                )
                EvidenceBadge(
                    title:
                        "\(confidenceLabel(claim.confidence)) confidence",
                    systemImage: "gauge.with.dots.needle.50percent"
                )
            }
            evidenceAnchors(
                context: title,
                claim: claim,
                presentation: presentation
            )
        }
    }

    @ViewBuilder
    private func claimsView(
        _ title: String,
        claims: [EvidenceLinkedClaim],
        presentation: AnalysisReviewPresentation
    ) -> some View {
        if !claims.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(
                    Array(claims.enumerated()),
                    id: \.offset
                ) { index, claim in
                    claimView(
                        claims.count == 1
                            ? title
                            : "\(title) \(index + 1)",
                        claim: claim,
                        presentation: presentation
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func evidenceAnchors(
        context: String,
        claim: EvidenceLinkedClaim,
        presentation: AnalysisReviewPresentation
    ) -> some View {
        if claim.evidenceRevisions.isEmpty {
            WorkflowStateView(
                title: "No supporting evidence reference",
                detail:
                    "This claim is explicitly unsupported and no evidence is implied.",
                systemImage: "link.badge.plus",
                tone: .neutral
            )
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(
                    Array(
                        claim.evidenceRevisions.enumerated()
                    ),
                    id: \.offset
                ) { _, reference in
                    if let evidence = presentation.evidence(
                        for: reference
                    ) {
                        EvidenceAnchor(evidence: evidence) {
                            evidenceSelection =
                                AnalysisEvidenceSelection(
                                    context: context,
                                    claim: claim,
                                    evidenceReference: reference
                                )
                            inspectorIsPresented = true
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 3) {
                            EvidenceBadge(
                                title:
                                    "Unresolved exact evidence",
                                systemImage:
                                    "exclamationmark.triangle"
                            )
                            Text(
                                "\(reference.logicalID.canonicalString) @ \(reference.revisionID.canonicalString)"
                            )
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        }
                    }
                }
                let unresolved =
                    presentation.unresolvedEvidenceCount(
                        for: claim
                    )
                if unresolved > 0 {
                    Text(
                        "\(unresolved) exact evidence reference(s) failed closed."
                    )
                    .font(.caption)
                    .foregroundStyle(BlueMinutesColors.error)
                }
            }
        }
    }

    private func representedName(
        _ reference: SemanticRevisionReference,
        presentation: AnalysisReviewPresentation
    ) -> String {
        presentation.representedName(for: reference)
            ?? "Unresolved exact entity "
                + reference.logicalID.canonicalString
                + " @ "
                + reference.revisionID.canonicalString
    }

    private func issueName(
        _ reference: SemanticRevisionReference,
        presentation: AnalysisReviewPresentation
    ) -> String {
        presentation.issueName(for: reference)
            ?? "Unresolved exact issue "
                + reference.logicalID.canonicalString
                + " @ "
                + reference.revisionID.canonicalString
    }

    private var positionSelection: Binding<PositionID?> {
        Binding(
            get: { sceneState.analysis.selectedPositionID },
            set: { sceneState.requestAnalysisSelection($0) }
        )
    }

    private func short(_ value: String) -> String {
        value.count > 16 ? String(value.prefix(16)) + "…" : value
    }

    private func confidenceLabel(
        _ confidence: ConfidenceScore
    ) -> String {
        let percent = Double(confidence.millionths) / 10_000
        return percent.formatted(
            .number.precision(.fractionLength(1))
        ) + "%"
    }

    private func label(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func time(_ milliseconds: Int64) -> String {
        (Double(milliseconds) / 1_000).formatted(
            .number.precision(.fractionLength(1))
        ) + " s"
    }
}

private struct PositionChoice: Identifiable {
    let value: PositionType
    let label: String
    var id: String { value.encodedValue }

    static let all: [Self] = [
        Self(value: .supports, label: "Supports"),
        Self(value: .opposes, label: "Opposes"),
        Self(value: .requests, label: "Requests"),
        Self(value: .proposes, label: "Proposes"),
        Self(value: .reservesPosition, label: "Reserves position"),
        Self(value: .supportsWithConditions, label: "Supports with conditions"),
        Self(value: .opposesWithQualification, label: "Opposes with qualification"),
        Self(value: .noStatedPosition, label: "No stated position (user conclusion)"),
        Self(value: .uncertain, label: "Uncertain")
    ]
}

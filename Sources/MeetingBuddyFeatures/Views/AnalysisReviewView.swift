import MeetingBuddyApplication
import MeetingBuddyDomain
import Observation
import SwiftUI

struct AnalysisReviewView: View {
    @Bindable var store: MediaReviewStore
    @State private var selectedPositionRevisionID: RevisionID?
    @State private var positionType: PositionType = .uncertain
    @State private var statementDraft = ""
    @State private var reservationsDraft = ""
    @State private var conditionsDraft = ""

    var body: some View {
        Group {
            if let review = store.analysisReview {
                reviewWorkspace(review)
            } else {
                setupView
            }
        }
        .onChange(of: selectedPositionRevisionID) { _, _ in
            loadPositionDrafts()
        }
        .onChange(of: store.analysisReview?.ledger.ledgerID) { _, _ in
            reconcileSelection()
        }
        .onChange(of: store.analysisReview?.positions.map(\.revision.revisionID)) { _, _ in
            reconcileSelection()
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
                                Task { await store.startAnalysis() }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                coverageHeader(review)
                delegationCards(review)
                interventionCards(review)
                positionEditor(review)
            }
            .padding(24)
            .frame(maxWidth: 1_020, alignment: .leading)
        }
    }

    private func coverageHeader(_ review: AnalysisReviewBundle) -> some View {
        GroupBox("Published analysis proof") {
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
                GridRow { Text("Prompt modules"); Text(review.ledger.promptModules.map { "\($0.identifier)@\($0.version)" }.joined(separator: ", ")) }
                GridRow { Text("Input digest"); Text(short(review.ledger.inputPackageDigest.lowercaseHex)).monospaced() }
                GridRow { Text("Ledger revision"); Text(short(review.ledger.ledgerID.canonicalString)).monospaced() }
            }
            .padding()
        }
    }

    private func delegationCards(_ review: AnalysisReviewBundle) -> some View {
        GroupBox("Delegation-position cards") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(review.delegationPositionCards, id: \.revision.revisionID) { card in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(representedName(card.representedEntityRevision, in: review))
                                .font(.headline)
                            Text("· " + issueName(card.issueRevision, in: review))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if cardIsStale(card, in: review) {
                                Label("Stale after correction", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            } else {
                                Text(card.reviewStatus.encodedValue)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        claimView("Overall position", claim: card.overallPosition)
                        claimsView("Reservations", claims: card.reservations)
                        claimsView("Conditions", claims: card.conditions)
                        LabeledContent(
                            "Exact inputs",
                            value: "\(card.positionRevisions.count) position · \(card.speakingCapacityRevisions.count) capacity revisions"
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

    private func interventionCards(_ review: AnalysisReviewBundle) -> some View {
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
                        claimView("Summary", claim: card.shortSummary)
                        LabeledContent(
                            "Typed objects",
                            value: "\(card.positionRevisions.count) position · \(card.commitmentRevisions.count) commitment · \(card.decisionRevisions.count) decision"
                        )
                        .font(.caption)
                    }
                }
            }
            .padding()
        }
    }

    private func positionEditor(_ review: AnalysisReviewBundle) -> some View {
        GroupBox("Inspect and correct positions") {
            HSplitView {
                List(
                    review.positions,
                    id: \.revision.revisionID,
                    selection: $selectedPositionRevisionID
                ) { position in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(position.statement.text).lineLimit(2)
                        Text("\(position.positionType.encodedValue) · \(position.reviewStatus.encodedValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(position.revision.revisionID)
                }
                .frame(minWidth: 260, idealWidth: 320, minHeight: 360)

                if let position = selectedPosition(in: review) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledContent("Actor revision", value: short(position.actorRevision.logicalID.canonicalString))
                            LabeledContent("Represented entity", value: representedName(position.representedEntityRevision, in: review))
                            LabeledContent("Speaking capacity revision", value: short(position.speakingCapacityRevision.revisionID.canonicalString))
                            LabeledContent("Issue", value: issueName(position.issueRevision, in: review))
                            LabeledContent("Claim taxonomy", value: position.statement.taxonomy.encodedValue)
                            LabeledContent("Evidence support", value: position.statement.supportStatus.encodedValue)
                            LabeledContent("Evidence revisions", value: String(position.statement.evidenceRevisions.count))
                            LabeledContent("Comparison state", value: position.comparisonState.encodedValue)
                            LabeledContent("Revision", value: short(position.revision.revisionID.canonicalString))
                                .monospaced()
                            Picker("Position type", selection: $positionType) {
                                ForEach(PositionChoice.all) { choice in
                                    Text(choice.label).tag(choice.value)
                                }
                            }
                            Text("Statement").font(.headline)
                            TextEditor(text: $statementDraft)
                                .frame(minHeight: 110)
                                .overlay { RoundedRectangle(cornerRadius: 6).stroke(.separator) }
                            Text("Reservations — one per line").font(.headline)
                            TextEditor(text: $reservationsDraft)
                                .frame(minHeight: 70)
                                .overlay { RoundedRectangle(cornerRadius: 6).stroke(.separator) }
                            Text("Conditions — one per line").font(.headline)
                            TextEditor(text: $conditionsDraft)
                                .frame(minHeight: 70)
                                .overlay { RoundedRectangle(cornerRadius: 6).stroke(.separator) }
                            Text("Saving creates an immutable user-confirmed Position revision. Dependent cards remain in history and are marked stale; they are not silently rewritten.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Save Confirmed Position Revision") {
                                Task {
                                    await store.correctPosition(
                                        revisionID: position.revision.revisionID,
                                        positionType: positionType,
                                        statement: statementDraft,
                                        reservations: lines(reservationsDraft),
                                        conditions: lines(conditionsDraft)
                                    )
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                store.isWorking
                                    || statementDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    private func claimView(_ label: String, claim: EvidenceLinkedClaim) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(claim.text)
            Text("\(claim.taxonomy.encodedValue) · \(claim.supportStatus.encodedValue) · \(claim.evidenceRevisions.count) evidence")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func claimsView(_ label: String, claims: [EvidenceLinkedClaim]) -> some View {
        if !claims.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                ForEach(Array(claims.enumerated()), id: \.offset) { _, claim in
                    Text("• " + claim.text)
                }
            }
        }
    }

    private func selectedPosition(in review: AnalysisReviewBundle) -> PositionV1? {
        review.positions.first { $0.revision.revisionID == selectedPositionRevisionID }
    }

    private func representedName(
        _ reference: SemanticRevisionReference,
        in review: AnalysisReviewBundle
    ) -> String {
        if let value = review.organizations.first(where: {
            $0.organizationID.canonicalString == reference.logicalID.canonicalString
        }) { return value.displayName }
        if let value = review.participants.first(where: {
            $0.participantID.canonicalString == reference.logicalID.canonicalString
        }) { return value.displayName }
        return "Unresolved entity " + short(reference.logicalID.canonicalString)
    }

    private func issueName(
        _ reference: SemanticRevisionReference,
        in review: AnalysisReviewBundle
    ) -> String {
        review.issues.first {
            $0.issueID.canonicalString == reference.logicalID.canonicalString
        }?.title.text ?? "Unresolved issue " + short(reference.logicalID.canonicalString)
    }

    private func cardIsStale(
        _ card: DelegationPositionCardV1,
        in review: AnalysisReviewBundle
    ) -> Bool {
        card.positionRevisions.contains { reference in
            review.positions.contains {
                $0.positionID.canonicalString == reference.logicalID.canonicalString
                    && $0.revision.revisionID != reference.revisionID
            }
        }
    }

    private func reconcileSelection() {
        guard let review = store.analysisReview else {
            selectedPositionRevisionID = nil
            return
        }
        if selectedPosition(in: review) == nil {
            selectedPositionRevisionID = review.positions.first?.revision.revisionID
        }
        loadPositionDrafts()
    }

    private func loadPositionDrafts() {
        guard let review = store.analysisReview,
              let position = selectedPosition(in: review)
        else {
            positionType = .uncertain
            statementDraft = ""
            reservationsDraft = ""
            conditionsDraft = ""
            return
        }
        positionType = position.positionType
        statementDraft = position.statement.text
        reservationsDraft = position.reservations.map(\.text).joined(separator: "\n")
        conditionsDraft = position.conditions.map(\.text).joined(separator: "\n")
    }

    private func lines(_ value: String) -> [String] {
        value.split(whereSeparator: \.isNewline).map(String.init)
    }

    private func short(_ value: String) -> String {
        value.count > 16 ? String(value.prefix(16)) + "…" : value
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

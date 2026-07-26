import MeetingBuddyApplication
import SwiftUI

struct UNWebTVMetadataView: View {
    @Bindable var store: MediaReviewStore
    @Bindable var sceneState: MediaReviewSceneState
    @Environment(\.blueMinutesReadingWidth)
    private var readingWidth

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                requestSection
                if let candidate = store.webMetadataCandidate {
                    candidateSection(candidate)
                    reviewSection
                }
                fallbackSection
            }
            .padding(28)
            .frame(maxWidth: readingWidth.points, alignment: .leading)
        }
    }

    private var requestSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            EditorialSectionHeader(
                "Official-page metadata only",
                detail:
                    "BlueMinutes is not affiliated with or endorsed by the United Nations. This bounded helper reads metadata from one exact official asset page only."
            )
            TextField(
                "https://webtv.un.org/en/asset/…/…",
                text: $sceneState.unWebTVURL
            )
            .textFieldStyle(.roundedBorder)
            Toggle(
                "Authorize one foreground GET to this exact official UN Web TV asset page. Do not fetch player, media, playlists, scripts, or subresources.",
                isOn: $sceneState.unWebTVNetworkAuthorized
            )
            .toggleStyle(.checkbox)
            .fixedSize(horizontal: false, vertical: true)

            fetchReadiness

            HStack {
                if let officialURL = sceneState.validatedUNWebTVURL {
                    Link("Open Official Page", destination: officialURL)
                }
                Spacer()
                Button("Fetch Metadata Candidate") {
                    Task {
                        await store.fetchUNWebTVMetadata(
                            using: sceneState
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(fetchBlockedReason != nil)
                .accessibilityHint(
                    fetchBlockedReason
                        ?? "Perform one foreground metadata-only request to this exact official page."
                )
            }
            Text(
                "Accepted URLs use HTTPS, the exact webtv.un.org host, a supported locale, and the bounded /asset/{collection}/{asset} shape with no query, fragment, user information, or custom port."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var fetchReadiness: some View {
        Group {
            if store.isWorking {
                WorkflowStateView(
                    title: "Metadata request in progress",
                    detail:
                        "The single foreground request remains bounded to official-page metadata.",
                    systemImage: "arrow.triangle.2.circlepath",
                    tone: .working
                )
            } else if let fetchBlockedReason {
                WorkflowStateView(
                    title: "Metadata request blocked",
                    detail: fetchBlockedReason,
                    systemImage: "exclamationmark.circle",
                    tone: .warning
                )
            } else {
                WorkflowStateView(
                    title: "Ready for one metadata request",
                    detail:
                        "Authorization applies only to this visible foreground request and resets after a candidate is returned.",
                    systemImage: "checkmark.circle",
                    tone: .ready
                )
            }
        }
        .accessibilityIdentifier("BlueMinutes.UNWebTV.FetchReadiness")
    }

    private func candidateSection(
        _ candidate: UNWebTVMetadataCandidate
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            EditorialSectionHeader(
                "Untrusted metadata candidate",
                detail:
                    "Every candidate remains untrusted data until reviewed locally."
            )
            WorkflowStateView(
                title: "Candidate requires review",
                detail:
                    "No player entry, media URL, cookie, token, playlist, or download handle is present.",
                systemImage: "doc.text.magnifyingglass",
                tone: .warning
            )
            LabeledContent(
                "Final official URL",
                value: candidate.finalURL.absoluteString
            )
            LabeledContent(
                "Review required",
                value:
                    candidate.requiresReview
                    ? "Yes"
                    : "Still review before use"
            )
            ForEach(candidate.fields) { field in
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        field.field.rawValue
                            .replacingOccurrences(
                                of: "_",
                                with: " "
                            )
                            .capitalized
                    )
                    .font(.caption.weight(.semibold))
                    Text(field.value)
                        .textSelection(.enabled)
                    Text(
                        "Parser v\(field.provenance.parserVersion) • \(field.provenance.source.rawValue) • \(field.provenance.sourceKey) • \(field.provenance.confidence.rawValue) confidence • SHA-256 \(field.provenance.normalizedValueDigest.lowercaseHex.prefix(12))…"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }
            Text("Page text is data, never instructions.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            EditorialSectionHeader(
                "Local review draft",
                detail:
                    "Corrections stay in this scene as an unpublished draft. There is no persistence action in the current application contract."
            )
            Form {
                TextField(
                    "Reviewed title",
                    text: $sceneState.reviewedUNTitle
                )
                TextField(
                    "Reviewed description",
                    text: $sceneState.reviewedUNDescription,
                    axis: .vertical
                )
                TextField(
                    "Reviewed production date",
                    text: $sceneState.reviewedUNProductionDate
                )
                TextField(
                    "Reviewed language availability",
                    text: $sceneState.reviewedUNLanguageAvailability
                )
                LabeledContent("Media acquisition", value: "Not authorized and not implemented")
            }
            .formStyle(.columns)
            Text(
                "Metadata alone does not create a media SourceAsset or grant download, capture, analysis, or redistribution rights."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var fallbackSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            EditorialSectionHeader(
                "Safe fallback",
                detail:
                    "Unsupported or changed pages fail back to explicit local review."
            )
            WorkflowStateView(
                title: "Manual review remains available",
                detail:
                    "Open the exact official page, enter metadata manually, and use Local Media only for a separately authorized user-selected file. Universal UN Web TV support is not claimed.",
                systemImage: "hand.raised",
                tone: .neutral
            )
        }
    }

    private var fetchBlockedReason: String? {
        IntakeSurfacePresentation.unWebTVFetchBlockedReason(
            url: sceneState.unWebTVURL,
            isWorking: store.isWorking,
            networkAuthorized: sceneState.unWebTVNetworkAuthorized
        )
    }
}

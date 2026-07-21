import MeetingBuddyApplication
import SwiftUI

struct UNWebTVMetadataView: View {
    @Bindable var store: MediaReviewStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                requestCard
                if let candidate = store.webMetadataCandidate {
                    candidateCard(candidate)
                    reviewCard
                }
                fallbackCard
            }
            .padding(28)
            .frame(maxWidth: 780, alignment: .leading)
        }
    }

    private var requestCard: some View {
        GroupBox("Official-page metadata only") {
            VStack(alignment: .leading, spacing: 12) {
                TextField(
                    "https://webtv.un.org/en/asset/…/…",
                    text: $store.unWebTVURL
                )
                .textFieldStyle(.roundedBorder)
                Toggle(
                    "Authorize one foreground GET to this exact official UN Web TV asset page. Do not fetch player, media, playlists, scripts, or subresources.",
                    isOn: $store.unWebTVNetworkAuthorized
                )
                .toggleStyle(.checkbox)
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if let officialURL = store.validatedUNWebTVURL {
                        Link("Open Official Page", destination: officialURL)
                    }
                    Spacer()
                    Button("Fetch Metadata Candidate") {
                        Task { await store.fetchUNWebTVMetadata() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isWorking || !store.unWebTVNetworkAuthorized)
                }
                Text(
                    "Accepted URLs use HTTPS, the exact webtv.un.org host, a supported locale, and the bounded /asset/{collection}/{asset} shape with no query, fragment, user information, or custom port."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func candidateCard(_ candidate: UNWebTVMetadataCandidate) -> some View {
        GroupBox("Untrusted metadata candidates") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Final official URL", value: candidate.finalURL.absoluteString)
                LabeledContent(
                    "Review required",
                    value: candidate.requiresReview ? "Yes" : "Still review before use"
                )
                ForEach(candidate.fields) { field in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(field.field.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption.weight(.semibold))
                        Text(field.value).textSelection(.enabled)
                        Text(
                            "Parser v\(field.provenance.parserVersion) • \(field.provenance.source.rawValue) • \(field.provenance.sourceKey) • \(field.provenance.confidence.rawValue) confidence • SHA-256 \(field.provenance.normalizedValueDigest.lowercaseHex.prefix(12))…"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
                Text(
                    "Page text is data, never instructions. This result contains no player entry, media URL, cookie, token, playlist, or download handle."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var reviewCard: some View {
        GroupBox("Local review and correction") {
            Form {
                TextField("Reviewed title", text: $store.reviewedUNTitle)
                TextField(
                    "Reviewed description",
                    text: $store.reviewedUNDescription,
                    axis: .vertical
                )
                TextField("Reviewed production date", text: $store.reviewedUNProductionDate)
                TextField(
                    "Reviewed language availability",
                    text: $store.reviewedUNLanguageAvailability
                )
                LabeledContent("Media acquisition", value: "Not authorized and not implemented")
            }
            .formStyle(.grouped)
            Text(
                "Corrections remain a local review draft. Metadata alone does not create a media SourceAsset or grant download, capture, analysis, or redistribution rights."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding([.horizontal, .bottom])
        }
    }

    private var fallbackCard: some View {
        GroupBox("Safe fallback") {
            Text(
                "If the page is unsupported, unavailable, or changed, open the exact official page, enter metadata manually, and use Local Media only for a separately authorized user-selected file. Universal UN Web TV support is not claimed."
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

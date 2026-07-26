import MeetingBuddyApplication
import MeetingBuddyDomain
import SwiftUI

struct BriefingSectionEditor: View {
    let review: BriefingReviewBundle
    let sections: [BriefingSectionV1]
    @Binding var selectedSectionType:
        BriefingSectionType?
    @Binding var draftItemTexts:
        [BriefingItemID: String]
    @Binding var draftIsLocked: Bool
    let draftSourceIsCurrent: Bool
    let draftIsDirty: Bool
    let storeIsWorking: Bool
    let briefingJobIsActive: Bool
    let interactionIsLocked: Bool
    let navigationIsPending: Bool
    let save: @MainActor () -> Void
    let regenerate: @MainActor (
        BriefingSectionType
    ) -> Void

    var body: some View {
        GroupBox("Edit and confirm one section") {
            VStack(alignment: .leading, spacing: 12) {
                EditorialSectionHeader(
                    "Section Revision Editor",
                    detail:
                        "Saving publishes one immutable user-confirmed successor. Other sections remain unchanged."
                )
                sectionPicker
                if let section = selectedSection {
                    editor(for: section)
                }
            }
            .padding()
        }
    }

    private var sectionPicker: some View {
        Picker(
            "Section",
            selection: $selectedSectionType
        ) {
            Text("Select a section")
                .tag(BriefingSectionType?.none)
            ForEach(sections, id: \.sectionType) {
                section in
                Text(section.title)
                    .tag(Optional(section.sectionType))
            }
        }
    }

    private func editor(
        for section: BriefingSectionV1
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(section)
            draftState
            itemEditors(section)
            sectionActions(section)
            preservedRevisionNote(section)
        }
    }

    private func sectionHeader(
        _ section: BriefingSectionV1
    ) -> some View {
        HStack {
            Label(
                section.manualEditStatus == .userEdited
                    ? "Preserved user revision"
                    : "Generated revision",
                systemImage:
                    section.manualEditStatus == .userEdited
                    ? "person.crop.circle.badge.checkmark"
                    : "apple.intelligence"
            )
            Spacer()
            Toggle(
                "Lock this revision",
                isOn: $draftIsLocked
            )
            .toggleStyle(.switch)
        }
    }

    @ViewBuilder
    private var draftState: some View {
        if !review.isCurrent {
            WorkflowStateView(
                title:
                    "Section mutations are blocked",
                detail:
                    "This publication is stale. A current Briefing publication must be produced through the existing application workflow before saving or regenerating a section.",
                systemImage: "lock.fill",
                tone: .failure
            )
        } else if !draftSourceIsCurrent {
            WorkflowStateView(
                title: "Draft source revision changed",
                detail:
                    "Keep or copy this draft, then review the current section revision before saving.",
                systemImage:
                    "exclamationmark.triangle.fill",
                tone: .failure
            )
        } else if draftIsDirty {
            WorkflowStateView(
                title: "Unpublished section draft",
                detail:
                    "The draft is local to this window until you save and confirm it.",
                systemImage: "square.and.pencil",
                tone: .warning
            )
        } else {
            WorkflowStateView(
                title: "Published section loaded",
                detail:
                    "A clean section can still be explicitly confirmed without changing its text.",
                systemImage: "checkmark.circle",
                tone: .success
            )
        }
    }

    private func itemEditors(
        _ section: BriefingSectionV1
    ) -> some View {
        ForEach(
            Array(section.items.enumerated()),
            id: \.element.itemID
        ) { index, item in
            BriefingItemTextEditor(
                sectionTitle: section.title,
                itemLabel: item.label,
                itemOrdinal: index + 1,
                evidenceReferenceCount:
                    item.claim.evidenceRevisions.count,
                accessibilityIdentifier:
                    "BlueMinutes.Briefing.ItemEditor.\(item.itemID.canonicalString)",
                text: itemBinding(item)
            )
        }
    }

    private func sectionActions(
        _ section: BriefingSectionV1
    ) -> some View {
        let availability = actionAvailability(
            for: section
        )
        return HStack {
            Button("Save and Confirm Section") {
                save()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!availability.canSaveSection)

            Button("Regenerate Only This Section") {
                regenerate(section.sectionType)
            }
            .disabled(
                !availability.canRegenerateSection
            )
        }
    }

    @ViewBuilder
    private func preservedRevisionNote(
        _ section: BriefingSectionV1
    ) -> some View {
        if section.locked
            || section.manualEditStatus == .userEdited
        {
            Text(
                "Automatic regeneration cannot overwrite this preserved user revision."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var selectedSection: BriefingSectionV1? {
        sections.first {
            $0.sectionType == selectedSectionType
        }
    }

    private func itemBinding(
        _ item: BriefingSectionItem
    ) -> Binding<String> {
        Binding(
            get: {
                draftItemTexts[item.itemID]
                    ?? item.claim.text
            },
            set: {
                draftItemTexts[item.itemID] = $0
            }
        )
    }

    private func actionAvailability(
        for section: BriefingSectionV1
    ) -> BriefingReviewActionAvailability {
        BriefingReviewActionAvailability(
            publicationIsCurrent: review.isCurrent,
            publicationIsHumanConfirmed:
                review.isHumanConfirmed,
            draftIsComplete:
                draftsAreComplete(section),
            draftIsDirty: draftIsDirty,
            draftSourceIsCurrent:
                draftSourceIsCurrent,
            sectionIsLocked: section.locked,
            sectionIsUserEdited:
                section.manualEditStatus == .userEdited,
            storeIsWorking: storeIsWorking,
            briefingJobIsActive:
                briefingJobIsActive,
            interactionIsLocked:
                interactionIsLocked,
            navigationIsPending:
                navigationIsPending
        )
    }

    private func draftsAreComplete(
        _ section: BriefingSectionV1
    ) -> Bool {
        Set(draftItemTexts.keys)
            == Set(section.items.map(\.itemID))
            && draftItemTexts.values.allSatisfy {
                let value = $0.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                return !value.isEmpty
                    && value == $0
                    && value.utf8.count <= 16_384
            }
    }
}

struct BriefingItemTextEditor: View {
    let sectionTitle: String
    let itemLabel: String?
    let itemOrdinal: Int
    let evidenceReferenceCount: Int
    let accessibilityIdentifier: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                "Evidence-linked item · \(evidenceReferenceCount) exact refs"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 88)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary)
                }
                .accessibilityIdentifier(
                    accessibilityIdentifier
                )
                .accessibilityLabel(editorLabel)
                .accessibilityValue(text)
                .accessibilityHint(
                    "Edit this section item. Saving creates an immutable user-confirmed revision while retaining \(evidenceReferenceCount) exact evidence reference(s)."
                )
        }
    }

    private var editorLabel: String {
        "\(sectionTitle), \(itemLabel ?? "item \(itemOrdinal)") editor"
    }
}

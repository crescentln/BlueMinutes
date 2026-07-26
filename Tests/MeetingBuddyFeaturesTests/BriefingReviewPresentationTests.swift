import AppKit
import ApplicationServices
import MeetingBuddyDomain
import SwiftUI
import Testing
@testable import MeetingBuddyFeatures

@Suite
struct BriefingReviewPresentationTests {
    @Test
    func canonicalProjectionAcceptsOnlyTheRealThreeSectionContract() {
        #expect(
            BriefingSectionProjection.isCanonical(
                sectionTypes: [
                    .meetingOverview,
                    .majorIssues,
                    .majorDelegations
                ],
                orders: [1, 2, 3],
                uniqueLogicalIDCount: 3
            )
        )
        #expect(
            !BriefingSectionProjection.isCanonical(
                sectionTypes: [
                    .meetingOverview,
                    .majorDelegations,
                    .majorIssues
                ],
                orders: [1, 2, 3],
                uniqueLogicalIDCount: 3
            )
        )
        #expect(
            !BriefingSectionProjection.isCanonical(
                sectionTypes: [
                    .meetingOverview,
                    .majorIssues,
                    .majorDelegations
                ],
                orders: [1, 3, 2],
                uniqueLogicalIDCount: 3
            )
        )
        #expect(
            !BriefingSectionProjection.isCanonical(
                sectionTypes: [
                    .meetingOverview,
                    .majorIssues,
                    .majorDelegations
                ],
                orders: [1, 2, 3],
                uniqueLogicalIDCount: 2
            )
        )
    }

    @Test
    func currentCleanSectionExposesOnlyContractBackedActions() {
        let availability = makeAvailability()

        #expect(availability.canSaveSection)
        #expect(availability.canRegenerateSection)
        #expect(availability.canExport)
    }

    @Test
    func dirtyDraftCanSaveButCannotRegenerateOrExport() {
        let availability = makeAvailability(
            draftIsDirty: true
        )

        #expect(availability.canSaveSection)
        #expect(!availability.canRegenerateSection)
        #expect(!availability.canExport)
    }

    @Test
    func stalePublicationBlocksEveryMutationAndExport() {
        let availability = makeAvailability(
            publicationIsCurrent: false
        )

        #expect(!availability.canSaveSection)
        #expect(!availability.canRegenerateSection)
        #expect(!availability.canExport)
    }

    @Test
    func staleDraftSourceAndIncompleteTextBlockSave() {
        let staleSource = makeAvailability(
            draftSourceIsCurrent: false
        )
        let incompleteDraft = makeAvailability(
            draftIsComplete: false
        )

        #expect(!staleSource.canSaveSection)
        #expect(!staleSource.canExport)
        #expect(!incompleteDraft.canSaveSection)
    }

    @Test
    func preservedSectionsCannotRegenerate() {
        #expect(
            !makeAvailability(
                sectionIsLocked: true
            ).canRegenerateSection
        )
        #expect(
            !makeAvailability(
                sectionIsUserEdited: true
            ).canRegenerateSection
        )
    }

    @Test
    func everyActiveOperationGateBlocksCommands() {
        let working = makeAvailability(
            storeIsWorking: true
        )
        let activeJob = makeAvailability(
            briefingJobIsActive: true
        )
        let locked = makeAvailability(
            interactionIsLocked: true
        )
        let pendingNavigation = makeAvailability(
            navigationIsPending: true
        )

        for availability in [
            working,
            activeJob,
            locked,
            pendingNavigation
        ] {
            #expect(!availability.canSaveSection)
            #expect(!availability.canRegenerateSection)
        }
        #expect(!working.canExport)
        #expect(!activeJob.canExport)
        #expect(!locked.canExport)
        #expect(!pendingNavigation.canExport)
    }

    @Test @MainActor
    func itemEditorsExposeDistinctNativeAccessibilityContracts()
        throws
    {
        let title =
            "BlueMinutes Briefing Item Editor AX Probe"
        let identifiers = [
            "BlueMinutes.Briefing.ItemEditor.first",
            "BlueMinutes.Briefing.ItemEditor.second"
        ]
        let window = hostBriefingEditorWindow(
            title: title
        )
        defer {
            window.contentView = nil
            window.close()
        }

        let elements = try briefingAXElements(
            windowTitle: title,
            identifiers: Set(identifiers)
        )

        let first = try #require(
            elements[identifiers[0]]
        )
        let second = try #require(
            elements[identifiers[1]]
        )
        #expect(
            briefingAXString(
                first,
                attribute: kAXRoleAttribute
            ) == kAXTextAreaRole
        )
        #expect(
            briefingAXString(
                first,
                attribute: kAXDescriptionAttribute
            ) == "Major Issues, Financing editor"
        )
        #expect(
            briefingAXString(
                first,
                attribute: kAXValueAttribute
            ) == "Synthetic financing draft"
        )
        #expect(
            briefingAXString(
                first,
                attribute: kAXHelpAttribute
            )?.contains(
                "retaining 2 exact evidence reference(s)"
            ) == true
        )
        #expect(
            briefingAXString(
                second,
                attribute: kAXDescriptionAttribute
            ) == "Major Issues, item 2 editor"
        )
        #expect(
            briefingAXString(
                second,
                attribute: kAXValueAttribute
            ) == "Synthetic safeguards draft"
        )
        #expect(
            briefingAXString(
                first,
                attribute: kAXDescriptionAttribute
            ) != briefingAXString(
                second,
                attribute: kAXDescriptionAttribute
            )
        )
    }
}

private func makeAvailability(
    publicationIsCurrent: Bool = true,
    publicationIsHumanConfirmed: Bool = true,
    draftIsComplete: Bool = true,
    draftIsDirty: Bool = false,
    draftSourceIsCurrent: Bool = true,
    sectionIsLocked: Bool = false,
    sectionIsUserEdited: Bool = false,
    storeIsWorking: Bool = false,
    briefingJobIsActive: Bool = false,
    interactionIsLocked: Bool = false,
    navigationIsPending: Bool = false
) -> BriefingReviewActionAvailability {
    BriefingReviewActionAvailability(
        publicationIsCurrent:
            publicationIsCurrent,
        publicationIsHumanConfirmed:
            publicationIsHumanConfirmed,
        draftIsComplete: draftIsComplete,
        draftIsDirty: draftIsDirty,
        draftSourceIsCurrent:
            draftSourceIsCurrent,
        sectionIsLocked: sectionIsLocked,
        sectionIsUserEdited: sectionIsUserEdited,
        storeIsWorking: storeIsWorking,
        briefingJobIsActive: briefingJobIsActive,
        interactionIsLocked: interactionIsLocked,
        navigationIsPending: navigationIsPending
    )
}

@MainActor
private struct BriefingItemEditorAXProbe: View {
    @State private var first =
        "Synthetic financing draft"
    @State private var second =
        "Synthetic safeguards draft"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            BriefingItemTextEditor(
                sectionTitle: "Major Issues",
                itemLabel: "Financing",
                itemOrdinal: 1,
                evidenceReferenceCount: 2,
                accessibilityIdentifier:
                    "BlueMinutes.Briefing.ItemEditor.first",
                text: $first
            )
            BriefingItemTextEditor(
                sectionTitle: "Major Issues",
                itemLabel: nil,
                itemOrdinal: 2,
                evidenceReferenceCount: 1,
                accessibilityIdentifier:
                    "BlueMinutes.Briefing.ItemEditor.second",
                text: $second
            )
        }
        .padding()
    }
}

@MainActor
private func hostBriefingEditorWindow(
    title: String
) -> NSWindow {
    let application = NSApplication.shared
    if !application.isRunning {
        application.finishLaunching()
    }
    let contentRect = NSRect(
        x: 0,
        y: 0,
        width: 620,
        height: 420
    )
    let hostingView = NSHostingView(
        rootView: BriefingItemEditorAXProbe()
    )
    hostingView.frame = contentRect
    let window = NSWindow(
        contentRect: contentRect,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.title = title
    window.contentView = hostingView
    window.makeKeyAndOrderFront(nil)
    window.displayIfNeeded()
    hostingView.layoutSubtreeIfNeeded()
    RunLoop.main.run(
        until: Date(timeIntervalSinceNow: 0.05)
    )
    return window
}

@MainActor
private func briefingAXElements(
    windowTitle: String,
    identifiers: Set<String>
) throws -> [String: AXUIElement] {
    let application =
        AXUIElementCreateApplication(getpid())
    let deadline = Date(timeIntervalSinceNow: 1)
    var matchingWindow: AXUIElement?

    repeat {
        matchingWindow = briefingAXChildren(
            application,
            attribute: kAXWindowsAttribute
        ).first {
            briefingAXString(
                $0,
                attribute: kAXTitleAttribute
            ) == windowTitle
        }
        if matchingWindow == nil {
            RunLoop.main.run(
                until:
                    Date(
                        timeIntervalSinceNow: 0.02
                    )
            )
        }
    } while matchingWindow == nil
        && Date() < deadline

    guard let matchingWindow else {
        throw BriefingAXTestError
            .windowUnavailable(windowTitle)
    }
    var result: [String: AXUIElement] = [:]
    repeat {
        result.removeAll(keepingCapacity: true)
        collectBriefingAXElements(
            matchingWindow,
            identifiers: identifiers,
            depth: 0,
            result: &result
        )
        if result.count != identifiers.count {
            RunLoop.main.run(
                until:
                    Date(
                        timeIntervalSinceNow: 0.02
                    )
            )
        }
    } while result.count != identifiers.count
        && Date() < deadline
    return result
}

@MainActor
private func collectBriefingAXElements(
    _ element: AXUIElement,
    identifiers: Set<String>,
    depth: Int,
    result: inout [String: AXUIElement]
) {
    guard depth < 20 else { return }
    if let identifier = briefingAXString(
        element,
        attribute: kAXIdentifierAttribute
    ), identifiers.contains(identifier)
    {
        result[identifier] = element
    }
    for child in briefingAXChildren(
        element,
        attribute: kAXChildrenAttribute
    ) {
        collectBriefingAXElements(
            child,
            identifiers: identifiers,
            depth: depth + 1,
            result: &result
        )
    }
}

@MainActor
private func briefingAXChildren(
    _ element: AXUIElement,
    attribute: String
) -> [AXUIElement] {
    briefingAXValue(
        element,
        attribute: attribute
    ) as? [AXUIElement] ?? []
}

@MainActor
private func briefingAXString(
    _ element: AXUIElement,
    attribute: String
) -> String? {
    briefingAXValue(
        element,
        attribute: attribute
    ) as? String
}

@MainActor
private func briefingAXValue(
    _ element: AXUIElement,
    attribute: String
) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        element,
        attribute as CFString,
        &value
    ) == .success else {
        return nil
    }
    return value
}

private enum BriefingAXTestError: Error {
    case windowUnavailable(String)
}

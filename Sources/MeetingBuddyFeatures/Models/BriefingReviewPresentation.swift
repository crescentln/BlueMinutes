import MeetingBuddyDomain

struct BriefingReviewActionAvailability:
    Equatable, Sendable
{
    let canSaveSection: Bool
    let canRegenerateSection: Bool
    let canExport: Bool

    init(
        publicationIsCurrent: Bool,
        publicationIsHumanConfirmed: Bool,
        draftIsComplete: Bool,
        draftIsDirty: Bool,
        draftSourceIsCurrent: Bool,
        sectionIsLocked: Bool,
        sectionIsUserEdited: Bool,
        storeIsWorking: Bool,
        briefingJobIsActive: Bool,
        interactionIsLocked: Bool,
        navigationIsPending: Bool
    ) {
        let mutationIsAvailable =
            publicationIsCurrent
                && !storeIsWorking
                && !briefingJobIsActive
                && !interactionIsLocked
                && !navigationIsPending

        canSaveSection =
            mutationIsAvailable
                && draftIsComplete
                && draftSourceIsCurrent

        canRegenerateSection =
            mutationIsAvailable
                && !sectionIsLocked
                && !sectionIsUserEdited
                && !draftIsDirty

        canExport =
            publicationIsCurrent
                && publicationIsHumanConfirmed
                && !draftIsDirty
                && draftSourceIsCurrent
                && !storeIsWorking
                && !briefingJobIsActive
                && !interactionIsLocked
                && !navigationIsPending
    }
}

enum BriefingSectionProjection {
    static let canonicalTypes: [BriefingSectionType] = [
        .meetingOverview,
        .majorIssues,
        .majorDelegations
    ]

    static func isCanonical(
        sectionTypes: [BriefingSectionType],
        orders: [UInt16],
        uniqueLogicalIDCount: Int
    ) -> Bool {
        sectionTypes == canonicalTypes
            && orders == [1, 2, 3]
            && uniqueLogicalIDCount == 3
    }
}

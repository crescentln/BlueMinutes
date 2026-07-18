import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
import Observation

@MainActor
@Observable
public final class MediaReviewStore {
    public private(set) var workspace: WorkspaceReview?
    public private(set) var pendingMedia: PendingMediaReview?
    public private(set) var importedSource: ImportedSourceReview?
    public private(set) var job: MediaJobReview?
    public private(set) var isWorking = false
    public private(set) var safeErrorMessage: String?

    public var selectedSection: MediaReviewSection? = .intake
    public var meetingTitle = ""
    public var dataClassification: DataClassification = .internal
    public var selectedTrack: MediaTrackIdentifier?
    public var speechSourceKind: SpeechSourceKind = .unknown
    public var languageTag = ""

    @ObservationIgnored
    private let workflow: any MediaReviewWorkflow
    @ObservationIgnored
    private var pollingTask: Task<Void, Never>?

    public init(workflow: any MediaReviewWorkflow) {
        self.workflow = workflow
    }

    public func restoreWorkspace() async {
        await perform {
            workspace = try await workflow.restoreWorkspace()
        }
    }

    public func openOrCreateWorkspace(at url: URL) async {
        await perform {
            pollingTask?.cancel()
            workspace = try await workflow.openOrCreateWorkspace(at: url)
            resetMediaState()
        }
    }

    public func inspectMedia(at url: URL) async {
        await perform {
            let review = try await workflow.inspectSelectedMedia(at: url)
            pendingMedia = review
            selectedTrack = review.inspection.audioTracks.count == 1
                ? review.inspection.audioTracks.first?.trackIdentifier
                : nil
            importedSource = nil
            job = nil
        }
    }

    public func discardPendingMedia() {
        workflow.discardPendingMedia()
        pendingMedia = nil
        selectedTrack = nil
    }

    public func importAndProcess() async {
        let title = meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.utf8.count <= 2_048 else {
            safeErrorMessage = "Enter a meeting title before importing media."
            return
        }
        guard let pendingMedia else {
            safeErrorMessage = "Choose a supported local audio or video file first."
            return
        }
        if pendingMedia.inspection.audioTracks.count > 1, selectedTrack == nil {
            safeErrorMessage = "Select one audio track before processing this media."
            return
        }
        let language: LanguageTag?
        let trimmedLanguage = languageTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedLanguage.isEmpty {
            language = nil
        } else {
            do {
                language = try LanguageTag(trimmedLanguage)
            } catch {
                safeErrorMessage = "Use a valid language tag such as en, fr, or zh-hans."
                return
            }
        }
        await perform {
            let result = try await workflow.importAndProcess(
                MediaImportSubmission(
                    meetingTitle: title,
                    dataClassification: dataClassification,
                    selectedTrack: selectedTrack,
                    speechSourceKind: speechSourceKind,
                    language: language
                )
            )
            importedSource = result.0
            job = result.1
            self.pendingMedia = nil
            beginPolling(jobID: result.1.jobID)
        }
    }

    public func cancelJob() async {
        guard let job else { return }
        await perform {
            self.job = try await workflow.cancel(jobID: job.jobID)
        }
    }

    public func retryJob() async {
        guard let job else { return }
        await perform {
            self.job = try await workflow.retry(jobID: job.jobID)
            beginPolling(jobID: job.jobID)
        }
    }

    public func clearError() {
        safeErrorMessage = nil
    }

    private func perform(_ operation: () async throws -> Void) async {
        guard !isWorking else {
            safeErrorMessage = "Wait for the current local operation to finish."
            return
        }
        safeErrorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await operation()
        } catch let error as LocalizedError {
            safeErrorMessage = error.errorDescription
                ?? "The local operation could not be completed."
        } catch {
            safeErrorMessage = "The local operation could not be completed."
        }
    }

    private func resetMediaState() {
        workflow.discardPendingMedia()
        pendingMedia = nil
        importedSource = nil
        job = nil
        selectedTrack = nil
        safeErrorMessage = nil
    }

    private func beginPolling(jobID: JobID) {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let current = try await workflow.jobReview(jobID: jobID)
                    job = current
                    if current.state.isTerminal { return }
                } catch {
                    safeErrorMessage = "Processing status is temporarily unavailable."
                    return
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }
}

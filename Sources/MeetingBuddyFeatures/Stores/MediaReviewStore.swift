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
    public private(set) var transcriptJob: MediaJobReview?
    public private(set) var routeReview: TranscriptRouteReview?
    public private(set) var transcriptReview: TranscriptReviewBundle?
    public private(set) var analysisJob: MediaJobReview?
    public private(set) var analysisRouteReview: AnalysisRouteReview?
    public private(set) var analysisReview: AnalysisReviewBundle?
    public private(set) var isWorking = false
    public private(set) var safeErrorMessage: String?

    public var selectedSection: MediaReviewSection? = .intake
    public var meetingTitle = ""
    public var dataClassification: DataClassification = .internal
    public var selectedTrack: MediaTrackIdentifier?
    public var speechSourceKind: SpeechSourceKind = .unknown
    public var languageTag = ""
    public var transcriptSourceLanguageTag = "en"
    public var transcriptTargetLanguageTag = ""
    public var manualTranscriptText = ""
    public var manualTranslationText = ""
    public var manualCoverageConfirmed = false

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

    public func refreshTranscriptRoute() async {
        guard let job, job.state == .succeeded else {
            safeErrorMessage = "Finish canonical local audio processing first."
            return
        }
        guard let submission = transcriptSubmission() else { return }
        await perform {
            routeReview = try await workflow.transcriptRoute(
                canonicalJobID: job.jobID,
                submission: submission
            )
        }
    }

    public func startTranscript() async {
        guard let job, job.state == .succeeded else {
            safeErrorMessage = "Finish canonical local audio processing first."
            return
        }
        guard let submission = transcriptSubmission() else { return }
        await perform {
            let route = try await workflow.transcriptRoute(
                canonicalJobID: job.jobID,
                submission: submission
            )
            routeReview = route
            guard route.isOnDeviceReady else {
                safeErrorMessage = "The selected installed models are unavailable. Use the manual local fallback."
                return
            }
            transcriptJob = try await workflow.startTranscript(
                canonicalJobID: job.jobID,
                submission: submission
            )
            if let transcriptJob { beginTranscriptPolling(jobID: transcriptJob.jobID) }
        }
    }

    public func publishManualTranscript() async {
        guard let job, job.state == .succeeded else {
            safeErrorMessage = "Finish canonical local audio processing first."
            return
        }
        guard let submission = transcriptSubmission() else { return }
        let transcript = manualTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty, transcript.utf8.count <= 65_536 else {
            safeErrorMessage = "Enter a manual transcript of at most 65,536 UTF-8 bytes."
            return
        }
        guard manualCoverageConfirmed else {
            safeErrorMessage = "Confirm that the manual text accounts for the complete recording."
            return
        }
        let translation: String?
        if submission.targetLanguage == nil {
            translation = nil
        } else {
            let value = manualTranslationText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.utf8.count <= 65_536 else {
                safeErrorMessage = "Enter the manual translation for the selected target language."
                return
            }
            translation = value
        }
        await perform {
            transcriptReview = try await workflow.publishManualTranscript(
                canonicalJobID: job.jobID,
                submission: submission,
                transcriptText: transcript,
                translatedText: translation,
                confirmsCompleteCoverage: manualCoverageConfirmed
            )
            selectedSection = .transcript
        }
    }

    public func loadTranscriptReview() async {
        guard let job, job.state == .succeeded else { return }
        await perform {
            transcriptReview = try await workflow.transcriptReview(canonicalJobID: job.jobID)
        }
    }

    public func correctTranscript(revisionID: RevisionID, text: String) async {
        guard let job else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 65_536 else {
            safeErrorMessage = "A corrected transcript segment must contain bounded text."
            return
        }
        await perform {
            transcriptReview = try await workflow.correctTranscript(
                canonicalJobID: job.jobID,
                revisionID: revisionID,
                text: trimmed
            )
        }
    }

    public func correctTranslation(revisionID: RevisionID, text: String) async {
        guard let job else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 65_536 else {
            safeErrorMessage = "A corrected translation segment must contain bounded text."
            return
        }
        await perform {
            transcriptReview = try await workflow.correctTranslation(
                canonicalJobID: job.jobID,
                revisionID: revisionID,
                text: trimmed
            )
        }
    }

    public func confirmSpeaker(
        transcriptRevisionID: RevisionID,
        displayName: String
    ) async {
        guard let job else { return }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 512 else {
            safeErrorMessage = "Enter a speaker name of at most 512 UTF-8 bytes."
            return
        }
        await perform {
            transcriptReview = try await workflow.confirmSpeaker(
                canonicalJobID: job.jobID,
                transcriptRevisionID: transcriptRevisionID,
                displayName: trimmed
            )
        }
    }

    public func refreshAnalysisRoute() async {
        guard let job, job.state == .succeeded else {
            safeErrorMessage = "Finish canonical local audio processing first."
            return
        }
        await perform {
            analysisRouteReview = try await workflow.analysisRoute(
                canonicalJobID: job.jobID
            )
        }
    }

    public func startAnalysis() async {
        guard let job, job.state == .succeeded else {
            safeErrorMessage = "Finish canonical local audio processing first."
            return
        }
        await perform {
            let route = try await workflow.analysisRoute(canonicalJobID: job.jobID)
            analysisRouteReview = route
            guard route.isOnDeviceReady else {
                safeErrorMessage = "The Apple on-device analysis model is unavailable for this meeting language. Existing local review data remains available."
                return
            }
            analysisJob = try await workflow.startAnalysis(canonicalJobID: job.jobID)
            if let analysisJob { beginAnalysisPolling(jobID: analysisJob.jobID) }
        }
    }

    public func loadAnalysisReview() async {
        guard let job, job.state == .succeeded else { return }
        await perform {
            analysisReview = try await workflow.analysisReview(canonicalJobID: job.jobID)
        }
    }

    public func correctPosition(
        revisionID: RevisionID,
        positionType: PositionType,
        statement: String,
        reservations: [String],
        conditions: [String]
    ) async {
        guard let job else { return }
        let trimmedStatement = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanReservations = Self.cleanClaims(reservations)
        let cleanConditions = Self.cleanClaims(conditions)
        guard !trimmedStatement.isEmpty, trimmedStatement.utf8.count <= 16_384 else {
            safeErrorMessage = "A corrected position statement must contain at most 16,384 UTF-8 bytes."
            return
        }
        guard cleanReservations.count == reservations.filter({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }).count,
            cleanConditions.count == conditions.filter({
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }).count
        else {
            safeErrorMessage = "Reservations and conditions must be unique bounded statements."
            return
        }
        await perform {
            analysisReview = try await workflow.correctPosition(
                canonicalJobID: job.jobID,
                revisionID: revisionID,
                positionType: positionType,
                statement: trimmedStatement,
                reservations: cleanReservations,
                conditions: cleanConditions
            )
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
        transcriptJob = nil
        routeReview = nil
        transcriptReview = nil
        analysisJob = nil
        analysisRouteReview = nil
        analysisReview = nil
        manualCoverageConfirmed = false
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

    private func beginTranscriptPolling(jobID: JobID) {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let current = try await workflow.jobReview(jobID: jobID)
                    transcriptJob = current
                    if current.state.isTerminal {
                        if current.state == .succeeded, let canonicalJob = job {
                            transcriptReview = try await workflow.transcriptReview(
                                canonicalJobID: canonicalJob.jobID
                            )
                        }
                        return
                    }
                } catch {
                    safeErrorMessage = "Transcript processing status is temporarily unavailable."
                    return
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    private func beginAnalysisPolling(jobID: JobID) {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let current = try await workflow.jobReview(jobID: jobID)
                    analysisJob = current
                    if current.state.isTerminal {
                        if current.state == .succeeded, let canonicalJob = job {
                            analysisReview = try await workflow.analysisReview(
                                canonicalJobID: canonicalJob.jobID
                            )
                        }
                        return
                    }
                } catch {
                    safeErrorMessage = "Analysis processing status is temporarily unavailable."
                    return
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    private static func cleanClaims(_ values: [String]) -> [String] {
        let cleaned = values.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty && $0.utf8.count <= 16_384 }
        guard Set(cleaned).count == cleaned.count else { return [] }
        return cleaned
    }

    private func transcriptSubmission() -> TranscriptStartSubmission? {
        let source = transcriptSourceLanguageTag.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = transcriptTargetLanguageTag.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let sourceLanguage = try LanguageTag(source)
            let targetLanguage = target.isEmpty ? nil : try LanguageTag(target)
            guard targetLanguage != sourceLanguage else {
                safeErrorMessage = "Source and target transcript languages must differ."
                return nil
            }
            return TranscriptStartSubmission(
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )
        } catch {
            safeErrorMessage = "Use valid language tags such as en, fr, or zh-hans."
            return nil
        }
    }
}

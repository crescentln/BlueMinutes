import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

enum IntakeSurfacePresentation {
    static let localMediaUnsavedDraftReason =
        "Save or discard every unpublished editor draft before replacing the current media workflow."

    static func localMediaImportBlockedReason(
        isInteractionLocked: Bool,
        hasUnsavedEditorChanges: Bool,
        isWorking: Bool,
        blocksMediaReplacement: Bool,
        meetingTitle: String,
        pendingMedia: PendingMediaReview?,
        selectedTrack: MediaTrackIdentifier?,
        languageTag: String
    ) -> String? {
        if isInteractionLocked {
            return "Wait for the current editor or workspace operation to finish."
        }
        if isWorking {
            return "Wait for the current local operation to finish."
        }
        if blocksMediaReplacement {
            return "Wait for the current media workflow to finish before replacing its source."
        }
        let title = meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title.utf8.count > 2_048 {
            return "Enter a meeting title before importing media."
        }
        guard let pendingMedia else {
            return "Choose a supported local audio or video file first."
        }
        if pendingMedia.inspection.audioTracks.count > 1, selectedTrack == nil {
            return "Select one audio track before processing this media."
        }
        if !isValidOptionalLanguageTag(languageTag) {
            return "Use a valid language tag such as en, fr, or zh-hans."
        }
        if hasUnsavedEditorChanges {
            return localMediaUnsavedDraftReason
        }
        return nil
    }

    static func recordingStartBlockedReason(
        isInteractionLocked: Bool,
        isWorking: Bool,
        blocksWorkspaceSwitch: Bool,
        setup: RecordingSetupReview?,
        meetingTitle: String,
        languageTag: String,
        mode: CaptureMode,
        selectedMicrophoneDeviceID: String?,
        recordingAcknowledged: Bool
    ) -> String? {
        if isInteractionLocked {
            return "Wait for the current editor or workspace operation to finish."
        }
        if isWorking {
            return "Wait for the current local operation to finish."
        }
        if blocksWorkspaceSwitch {
            return "Finish the current recording before starting another one."
        }
        guard let setup else {
            return "BlueMinutes is checking microphone and application-audio capabilities."
        }
        let title = meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title.utf8.count > 2_048 {
            return "Enter a meeting title before recording."
        }
        if !isValidOptionalLanguageTag(languageTag) {
            return "Use a valid language tag such as en, fr, or zh-hans."
        }
        if mode.requestedTrackKinds.contains(.microphone) {
            switch setup.capability.microphonePermission {
            case .authorized, .notDetermined:
                break
            case .denied:
                return "Microphone permission is denied for this capture mode."
            case .restricted:
                return "Microphone access is restricted for this capture mode."
            }
            if selectedMicrophoneDeviceID == nil {
                return "Select one microphone for this recording session."
            }
        }
        if mode.requestedTrackKinds.contains(.applicationAudio) {
            if !setup.capability.applicationAudioAvailable {
                return "One-application audio is unavailable on this macOS build."
            }
            if !setup.capability.systemPickerAvailable {
                return "The system application-audio picker is unavailable."
            }
        }
        if !recordingAcknowledged {
            return "A visible recording requires the participant, policy, and legal-responsibility acknowledgement."
        }
        return nil
    }

    static func unWebTVFetchBlockedReason(
        url: String,
        isWorking: Bool,
        networkAuthorized: Bool
    ) -> String? {
        if isWorking {
            return "Wait for the current local operation to finish."
        }
        let value = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if (try? ValidatedUNWebTVAssetURL(value)) == nil {
            return "Use an exact official UN Web TV asset URL such as https://webtv.un.org/en/asset/abc/asset-id."
        }
        if !networkAuthorized {
            return "Authorize this one foreground official-page metadata request."
        }
        return nil
    }

    static func recordingStateTitle(_ state: RecordingState) -> String {
        switch state {
        case .preparing: "Preparing"
        case .recording: "Recording"
        case .interrupted: "Interrupted"
        case .recovering: "Recovering retained audio"
        case .stopping: "Stopping"
        case .finalizing: "Finalizing and verifying"
        case .completed: "Completed"
        case .incomplete: "Incomplete recording retained"
        case .failed: "Recording failed"
        }
    }

    static func recordingStateExplanation(_ state: RecordingState) -> String {
        switch state {
        case .preparing:
            "The intent and exact source policy are durable; audio is not yet claimed as recording."
        case .recording:
            "Bounded audio packets are active and five-second CAF segments are sealed incrementally."
        case .interrupted:
            "Source continuity is no longer trusted. No device or application was substituted."
        case .recovering:
            "Sealed rows and CAF files are being re-proved after an interruption."
        case .stopping:
            "New packet admission is closed while bounded writers drain."
        case .finalizing:
            "Hashes, gaps, manifest, and local managed assets are being verified."
        case .completed:
            "All required selected tracks were verified and published with exact manifest provenance."
        case .incomplete:
            "Usable verified audio survives, but a gap or publication precondition prevents a complete claim."
        case .failed:
            "No verified usable audio was published; no zero-byte source was created."
        }
    }

    private static func isValidOptionalLanguageTag(_ rawValue: String) -> Bool {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || (try? LanguageTag(value)) != nil
    }
}

@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import CryptoKit
import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain
@preconcurrency import ScreenCaptureKit

public final class MacOSAudioCaptureProvider: CaptureCapabilityProvider,
    CaptureSourcePicker, AuthorizedAudioCaptureProvider, @unchecked Sendable
{
    private struct SelectionContext {
        let authorization: CaptureSelectionAuthorization
        let filter: SCContentFilter?
    }

    private struct PreparedContext {
        let prepared: PreparedCapture
        let request: PreparedCaptureRequest
        let filter: SCContentFilter?
    }

    private let picker = SystemApplicationPickerBridge()
    private let lock = NSLock()
    private var selections: [UUID: SelectionContext] = [:]
    private var preparedContexts: [UUID: PreparedContext] = [:]
    private var runtimes: [UUID: NativeCaptureRuntime] = [:]
    private let clock: @Sendable () -> UTCInstant

    public init(
        clock: @escaping @Sendable () -> UTCInstant = {
            try! UTCInstant(
                millisecondsSinceUnixEpoch: Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
            )
        }
    ) {
        self.clock = clock
    }

    public func snapshot() async -> CaptureCapabilitySnapshot {
        CaptureCapabilitySnapshot(
            microphonePermission: Self.permissionState(
                AVCaptureDevice.authorizationStatus(for: .audio)
            ),
            applicationAudioAvailable: Self.applicationSelectionIsAuditable,
            systemPickerAvailable: Self.applicationSelectionIsAuditable,
            checkedAt: clock()
        )
    }

    public func microphones() async throws -> [CaptureMicrophoneChoice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        return try discovery.devices
            .sorted { ($0.localizedName, $0.uniqueID) < ($1.localizedName, $1.uniqueID) }
            .map { device in
                let description = device.activeFormat.formatDescription
                let format = AVAudioFormat(cmAudioFormatDescription: description)
                return try CaptureMicrophoneChoice(
                    id: device.uniqueID,
                    displayName: device.localizedName,
                    audioFormat: CaptureAudioFormat(
                        sampleRateHertz: UInt32(format.sampleRate.rounded()),
                        channelCount: UInt16(format.channelCount),
                        channelLayout: "interleaved-pcm-s16le",
                        formatRevision: 1
                    )
                )
            }
    }

    public func requestSelection(
        _ request: CaptureSelectionRequest
    ) async throws -> CaptureSelectionAuthorization {
        let filter: SCContentFilter?
        if request.mode.requestedTrackKinds.contains(.applicationAudio) {
            guard Self.applicationSelectionIsAuditable else {
                throw CaptureProviderError.capabilityUnavailable(
                    "single_application_provenance_requires_macos_15_2"
                )
            }
            filter = try await picker.requestSingleApplicationFilter(
                excludedBundleID: Bundle.main.bundleIdentifier
            )
        } else {
            filter = nil
        }
        let selectedAt = clock()
        let applicationSourceToken = try filter.map {
            try Self.applicationToken(
                filter: $0,
                sessionID: request.sessionID,
                selectedAt: selectedAt
            )
        }
        let authorization = try CaptureSelectionAuthorization(
            sessionID: request.sessionID,
            epochID: request.epochID,
            mode: request.mode,
            microphoneDeviceID: request.microphoneDeviceID,
            applicationSourceToken: applicationSourceToken,
            selectedAt: selectedAt
        )
        lock.withLock {
            selections[authorization.authorizationID] = SelectionContext(
                authorization: authorization,
                filter: filter
            )
        }
        return authorization
    }

    public func prepare(_ request: PreparedCaptureRequest) async throws -> PreparedCapture {
        guard let context = lock.withLock({ selections.removeValue(forKey: request.authorization.authorizationID) }),
              context.authorization == request.authorization
        else {
            throw CaptureProviderError.authorizationExpired
        }

        if request.authorization.mode.requestedTrackKinds.contains(.microphone) {
            var status = AVCaptureDevice.authorizationStatus(for: .audio)
            if status == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
                status = AVCaptureDevice.authorizationStatus(for: .audio)
            }
            guard status == .authorized,
                  let deviceID = request.authorization.microphoneDeviceID,
                  Self.microphoneDevice(id: deviceID) != nil
            else {
                throw CaptureProviderError.permissionDenied(.microphone)
            }
        }
        guard !request.authorization.mode.requestedTrackKinds.contains(.applicationAudio)
                || context.filter != nil
        else {
            throw CaptureProviderError.invalidSelection
        }

        let prepared = PreparedCapture(
            authorizationID: request.authorization.authorizationID,
            sessionID: request.authorization.sessionID,
            epochID: request.authorization.epochID,
            mode: request.authorization.mode
        )
        lock.withLock {
            preparedContexts[prepared.preparationID] = PreparedContext(
                prepared: prepared,
                request: request,
                filter: context.filter
            )
        }
        return prepared
    }

    public func start(
        _ prepared: PreparedCapture,
        sink: any CapturedAudioPacketSink
    ) async throws -> CaptureHandle {
        guard let context = lock.withLock({ preparedContexts.removeValue(forKey: prepared.preparationID) }),
              context.prepared == prepared
        else {
            throw CaptureProviderError.authorizationExpired
        }

        let trackMap = Dictionary(uniqueKeysWithValues: context.request.tracks.map { ($0.kind, $0.trackID) })
        let relays = Dictionary(uniqueKeysWithValues: context.request.tracks.map { track in
            let relay = CapturePacketRelay(
                sink: sink,
                trackKind: track.kind,
                maximumQueuedDurationNanoseconds: context.request.maximumQueuedDurationNanoseconds
            )
            relay.start()
            return (track.kind, relay)
        })
        let nativeOutput = NativeAudioOutput(
            sessionID: prepared.sessionID,
            epochID: prepared.epochID,
            trackIDs: trackMap,
            relays: relays
        )
        let runtime: NativeCaptureRuntime
        do {
            switch prepared.mode {
            case .microphoneOnly:
                guard let deviceID = context.request.authorization.microphoneDeviceID,
                      let device = Self.microphoneDevice(id: deviceID)
                else { throw CaptureProviderError.invalidSelection }
                runtime = try startMicrophoneSession(device: device, output: nativeOutput, relays: relays)
            case .applicationAudioOnly, .microphoneAndApplicationAudio:
                guard let filter = context.filter else { throw CaptureProviderError.invalidSelection }
                runtime = try await startScreenCaptureStream(
                    filter: filter,
                    request: context.request,
                    output: nativeOutput,
                    relays: relays
                )
            }
        } catch {
            for relay in relays.values { relay.fail(.providerFailure("native_capture_start_failed")) }
            for relay in relays.values { await relay.finish() }
            if let error = error as? CaptureProviderError { throw error }
            throw CaptureProviderError.providerFailure("native_capture_start_failed")
        }

        let handle = CaptureHandle(sessionID: prepared.sessionID, epochID: prepared.epochID)
        lock.withLock { runtimes[handle.id] = runtime }
        return handle
    }

    public func stop(_ handle: CaptureHandle) async {
        guard let runtime = lock.withLock({ runtimes.removeValue(forKey: handle.id) }) else { return }
        runtime.invalidateFailureObserver()
        switch runtime.backend {
        case let .microphone(session):
            session.stopRunning()
        case let .screenCapture(stream):
            try? await stream.stopCapture()
        }
        for relay in runtime.relays.values { await relay.finish() }
    }

    private func startMicrophoneSession(
        device: AVCaptureDevice,
        output: NativeAudioOutput,
        relays: [CaptureTrackKind: CapturePacketRelay]
    ) throws -> NativeCaptureRuntime {
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        let dataOutput = AVCaptureAudioDataOutput()
        dataOutput.setSampleBufferDelegate(output, queue: output.callbackQueue)
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(dataOutput) else {
            session.commitConfiguration()
            throw CaptureProviderError.capabilityUnavailable("microphone_capture_configuration")
        }
        session.addInput(input)
        session.addOutput(dataOutput)
        session.commitConfiguration()
        let failureObserver = CaptureSessionFailureObserver(session: session) {
            for relay in relays.values {
                relay.fail(.sourceStopped(.microphone))
            }
        }
        session.startRunning()
        return NativeCaptureRuntime(
            backend: .microphone(session),
            output: output,
            relays: relays,
            failureObserver: failureObserver
        )
    }

    private func startScreenCaptureStream(
        filter: SCContentFilter,
        request: PreparedCaptureRequest,
        output: NativeAudioOutput,
        relays: [CaptureTrackKind: CapturePacketRelay]
    ) async throws -> NativeCaptureRuntime {
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.captureMicrophone = request.authorization.mode == .microphoneAndApplicationAudio
        if configuration.captureMicrophone {
            guard let microphoneDeviceID = request.authorization.microphoneDeviceID else {
                throw CaptureProviderError.invalidSelection
            }
            configuration.microphoneCaptureDeviceID = microphoneDeviceID
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.callbackQueue)
        if configuration.captureMicrophone {
            try stream.addStreamOutput(output, type: .microphone, sampleHandlerQueue: output.callbackQueue)
        }
        try await stream.startCapture()
        return NativeCaptureRuntime(
            backend: .screenCapture(stream),
            output: output,
            relays: relays,
            failureObserver: nil
        )
    }

    private static func microphoneDevice(id: String) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices.first { $0.uniqueID == id }
    }

    private static var applicationSelectionIsAuditable: Bool {
        if #available(macOS 15.2, *) { return true }
        return false
    }

    private static func applicationToken(
        filter: SCContentFilter,
        sessionID: RecordingSessionID,
        selectedAt: UTCInstant
    ) throws -> ContentDigest {
        guard #available(macOS 15.2, *),
              filter.includedApplications.count == 1,
              let application = filter.includedApplications.first
        else { throw CaptureProviderError.invalidSelection }
        let material = [
            sessionID.canonicalString,
            "single-application-audio",
            application.bundleIdentifier,
            String(application.processID),
            String(selectedAt.millisecondsSinceUnixEpoch),
            "48000",
            "2"
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return try ContentDigest(algorithm: .sha256, lowercaseHex: digest)
    }

    private static func permissionState(_ status: AVAuthorizationStatus) -> CapturePermissionState {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorized: .authorized
        @unknown default: .restricted
        }
    }
}

private final class NativeCaptureRuntime: @unchecked Sendable {
    enum Backend {
        case microphone(AVCaptureSession)
        case screenCapture(SCStream)
    }

    let backend: Backend
    let output: NativeAudioOutput
    let relays: [CaptureTrackKind: CapturePacketRelay]
    private let failureObserver: CaptureSessionFailureObserver?

    init(
        backend: Backend,
        output: NativeAudioOutput,
        relays: [CaptureTrackKind: CapturePacketRelay],
        failureObserver: CaptureSessionFailureObserver?
    ) {
        self.backend = backend
        self.output = output
        self.relays = relays
        self.failureObserver = failureObserver
    }

    func invalidateFailureObserver() {
        failureObserver?.invalidate()
    }
}

final class CaptureSessionFailureObserver: @unchecked Sendable {
    private let notificationCenter: NotificationCenter
    private let onFailure: @Sendable () -> Void
    private let lock = NSLock()
    private var tokens: [NSObjectProtocol] = []
    private var active = true
    private var delivered = false

    init(
        notificationCenter: NotificationCenter = .default,
        session: AVCaptureSession,
        onFailure: @escaping @Sendable () -> Void
    ) {
        self.notificationCenter = notificationCenter
        self.onFailure = onFailure
        for name in [
            AVCaptureSession.runtimeErrorNotification,
            AVCaptureSession.wasInterruptedNotification,
            AVCaptureSession.didStopRunningNotification
        ] {
            tokens.append(
                notificationCenter.addObserver(
                    forName: name,
                    object: session,
                    queue: nil
                ) { [weak self] _ in
                    self?.deliverFailureOnce()
                }
            )
        }
    }

    deinit {
        invalidate()
    }

    func invalidate() {
        let tokensToRemove = lock.withLock { () -> [NSObjectProtocol] in
            guard active else { return [] }
            active = false
            let values = tokens
            tokens.removeAll()
            return values
        }
        for token in tokensToRemove {
            notificationCenter.removeObserver(token)
        }
    }

    private func deliverFailureOnce() {
        let shouldDeliver = lock.withLock { () -> Bool in
            guard active, !delivered else { return false }
            delivered = true
            return true
        }
        if shouldDeliver { onFailure() }
    }
}

private final class NativeAudioOutput: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate,
    SCStreamOutput, SCStreamDelegate, @unchecked Sendable
{
    let callbackQueue = DispatchQueue(label: "MeetingBuddy.NativeAudioCapture", qos: .userInitiated)

    private let sessionID: RecordingSessionID
    private let epochID: RecordingEpochID
    private let trackIDs: [CaptureTrackKind: RecordingTrackID]
    private let relays: [CaptureTrackKind: CapturePacketRelay]
    private var sequences: [CaptureTrackKind: UInt64] = [:]
    private var formats: [CaptureTrackKind: CaptureAudioFormat] = [:]
    private var previousMediaEnd: [CaptureTrackKind: UInt64] = [:]

    init(
        sessionID: RecordingSessionID,
        epochID: RecordingEpochID,
        trackIDs: [CaptureTrackKind: RecordingTrackID],
        relays: [CaptureTrackKind: CapturePacketRelay]
    ) {
        self.sessionID = sessionID
        self.epochID = epochID
        self.trackIDs = trackIDs
        self.relays = relays
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        consume(sampleBuffer, kind: .microphone)
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        switch outputType {
        case .audio: consume(sampleBuffer, kind: .applicationAudio)
        case .microphone: consume(sampleBuffer, kind: .microphone)
        case .screen: break
        @unknown default: break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        for (kind, relay) in relays {
            relay.fail(.sourceStopped(kind))
        }
    }

    private func consume(_ sampleBuffer: CMSampleBuffer, kind: CaptureTrackKind) {
        guard let relay = relays[kind], let trackID = trackIDs[kind] else { return }
        do {
            let converted = try Self.convertToInterleavedInt16(sampleBuffer)
            if let prior = formats[kind], prior != converted.format {
                relay.fail(.formatChanged(kind))
                return
            }
            formats[kind] = converted.format
            let presentation = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard presentation.isValid, !presentation.isIndefinite else {
                relay.fail(.providerFailure("capture_timestamp_invalid"))
                return
            }
            let mediaStartValue = CMTimeConvertScale(
                presentation,
                timescale: 1_000_000_000,
                method: .roundTowardZero
            ).value
            guard mediaStartValue >= 0 else {
                relay.fail(.providerFailure("capture_timestamp_invalid"))
                return
            }
            let duration = UInt64(converted.frameCount) * 1_000_000_000
                / UInt64(converted.format.sampleRateHertz)
            let mediaStart = UInt64(mediaStartValue)
            let mediaEnd = mediaStart + duration
            if let previous = previousMediaEnd[kind] {
                let tolerance = 2_000_000_000 / UInt64(converted.format.sampleRateHertz)
                guard mediaStart <= previous + tolerance, mediaEnd > previous else {
                    relay.fail(.providerFailure("capture_time_discontinuity"))
                    return
                }
            }
            previousMediaEnd[kind] = mediaEnd
            let hostNow = CMClockGetTime(CMClockGetHostTimeClock())
            let hostEndValue = CMTimeConvertScale(
                hostNow,
                timescale: 1_000_000_000,
                method: .roundTowardZero
            ).value
            guard hostEndValue >= Int64(duration) else {
                relay.fail(.providerFailure("capture_host_clock_invalid"))
                return
            }
            let sequence = (sequences[kind] ?? 0) + 1
            sequences[kind] = sequence
            let packet = try CapturedAudioPacket(
                sessionID: sessionID,
                epochID: epochID,
                trackID: trackID,
                sequence: sequence,
                mediaRange: RecordingTimeRange(startNanoseconds: mediaStart, endNanoseconds: mediaEnd),
                hostRange: RecordingTimeRange(
                    startNanoseconds: UInt64(hostEndValue) - duration,
                    endNanoseconds: UInt64(hostEndValue)
                ),
                format: converted.format,
                frameCount: converted.frameCount,
                linearPCM: converted.data
            )
            _ = relay.enqueue(packet)
        } catch {
            relay.fail(.providerFailure("capture_pcm_conversion_failed"))
        }
    }

    private static func convertToInterleavedInt16(
        _ sampleBuffer: CMSampleBuffer
    ) throws -> (data: Data, frameCount: UInt32, format: CaptureAudioFormat) {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw CaptureProviderError.providerFailure("capture_audio_format_missing")
        }
        let inputFormat = AVAudioFormat(cmAudioFormatDescription: description)
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0,
              let inputBuffer = AVAudioPCMBuffer(
                  pcmFormat: inputFormat,
                  frameCapacity: frameCount
              )
        else {
            throw CaptureProviderError.providerFailure("capture_audio_buffer_invalid")
        }
        inputBuffer.frameLength = frameCount
        let copyStatus = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: inputBuffer.mutableAudioBufferList
        )
        guard copyStatus == noErr else {
            throw CaptureProviderError.providerFailure("capture_audio_copy_failed")
        }
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: inputFormat.sampleRate,
            channels: inputFormat.channelCount,
            interleaved: true
        ),
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: frameCount
            ),
            let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else {
            throw CaptureProviderError.providerFailure("capture_audio_converter_unavailable")
        }
        let inputSupply = AudioConverterInputSupply(inputBuffer)
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outputStatus in
            inputSupply.next(status: outputStatus)
        }
        guard status != .error,
              conversionError == nil,
              outputBuffer.frameLength > 0,
              let channelData = outputBuffer.int16ChannelData
        else {
            throw CaptureProviderError.providerFailure("capture_audio_conversion_failed")
        }
        let byteCount = Int(outputBuffer.frameLength)
            * Int(outputFormat.channelCount)
            * MemoryLayout<Int16>.size
        let data = Data(bytes: channelData[0], count: byteCount)
        return (
            data,
            UInt32(outputBuffer.frameLength),
            try CaptureAudioFormat(
                sampleRateHertz: UInt32(inputFormat.sampleRate.rounded()),
                channelCount: UInt16(inputFormat.channelCount),
                channelLayout: "interleaved-pcm-s16le",
                formatRevision: 1
            )
        )
    }
}

private final class SystemApplicationPickerBridge: NSObject, SCContentSharingPickerObserver,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var continuation: CheckedContinuation<SCContentFilter, any Error>?

    func requestSingleApplicationFilter(
        excludedBundleID: String?
    ) async throws -> SCContentFilter {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let accepted = lock.withLock { () -> Bool in
                    guard self.continuation == nil else { return false }
                    self.continuation = continuation
                    return true
                }
                guard accepted else {
                    continuation.resume(throwing: CaptureProviderError.directUserSelectionRequired)
                    return
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let picker = SCContentSharingPicker.shared
                    var configuration = SCContentSharingPickerConfiguration()
                    configuration.allowedPickerModes = .singleApplication
                    configuration.excludedBundleIDs = excludedBundleID.map { [$0] } ?? []
                    configuration.allowsChangingSelectedContent = false
                    picker.defaultConfiguration = configuration
                    picker.maximumStreamCount = 1
                    picker.add(self)
                    picker.isActive = true
                    picker.present()
                }
            }
        } onCancel: {
            self.finish(throwing: CaptureProviderError.directUserSelectionRequired)
        }
    }

    func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {
        finish(throwing: CaptureProviderError.directUserSelectionRequired)
    }

    func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        if #available(macOS 15.2, *), filter.includedApplications.count != 1 {
            finish(throwing: CaptureProviderError.invalidSelection)
            return
        }
        finish(returning: filter)
    }

    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        finish(throwing: CaptureProviderError.providerFailure("system_picker_failed"))
    }

    private func finish(returning filter: SCContentFilter) {
        let pending = lock.withLock { () -> CheckedContinuation<SCContentFilter, any Error>? in
            defer { continuation = nil }
            return continuation
        }
        deactivatePicker()
        pending?.resume(returning: filter)
    }

    private func finish(throwing error: any Error) {
        let pending = lock.withLock { () -> CheckedContinuation<SCContentFilter, any Error>? in
            defer { continuation = nil }
            return continuation
        }
        deactivatePicker()
        pending?.resume(throwing: error)
    }

    private func deactivatePicker() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let picker = SCContentSharingPicker.shared
            picker.remove(self)
            picker.isActive = false
        }
    }
}

private final class AudioConverterInputSupply: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(
        status: UnsafeMutablePointer<AVAudioConverterInputStatus>
    ) -> AVAudioBuffer? {
        lock.withLock {
            guard let buffer else {
                status.pointee = .endOfStream
                return nil
            }
            self.buffer = nil
            status.pointee = .haveData
            return buffer
        }
    }
}

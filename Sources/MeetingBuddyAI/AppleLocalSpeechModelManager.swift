import Foundation
import MeetingBuddyApplication
import Speech

public actor UnavailableLocalSpeechModelManager:
    LocalSpeechModelManaging
{
    public nonisolated let events:
        AsyncStream<LocalSpeechModelSnapshot>

    public init() {
        events = AsyncStream { continuation in
            continuation.finish()
        }
    }

    public func snapshot(
        languageTag: String
    ) -> LocalSpeechModelSnapshot {
        LocalSpeechModelSnapshot(
            languageTag: languageTag,
            resolvedLocaleIdentifier: nil,
            phase: .unsupported
        )
    }

    public func install(languageTag: String) async throws {
        throw AIProviderContractError.modelUnavailable(
            "Apple on-device Speech model management requires macOS 26 or later."
        )
    }

    public func pauseDownload() {}
    public func resumeDownload() {}
    public func cancelDownload() {}

    public func release(languageTag: String) async throws {
        throw AIProviderContractError.modelUnavailable(
            "Apple on-device Speech model management requires macOS 26 or later."
        )
    }
}

@available(macOS 26.0, *)
public actor AppleLocalSpeechModelManager:
    LocalSpeechModelManaging
{
    public nonisolated let events:
        AsyncStream<LocalSpeechModelSnapshot>

    private let continuation:
        AsyncStream<LocalSpeechModelSnapshot>.Continuation
    private var request: AssetInstallationRequest?
    private var downloadTask: Task<Void, Error>?
    private var progressTask: Task<Void, Never>?
    private var activeLanguageTag: String?

    public init() {
        let pair =
            AsyncStream<LocalSpeechModelSnapshot>
            .makeStream(
                bufferingPolicy: .bufferingNewest(32)
            )
        events = pair.stream
        continuation = pair.continuation
    }

    public func snapshot(
        languageTag: String
    ) async -> LocalSpeechModelSnapshot {
        do {
            let context = try await modelContext(
                languageTag: languageTag
            )
            let status = await AssetInventory.status(
                forModules: [context.transcriber]
            )
            return await makeSnapshot(
                languageTag: languageTag,
                locale: context.locale,
                status: status
            )
        } catch {
            return LocalSpeechModelSnapshot(
                languageTag: languageTag,
                resolvedLocaleIdentifier: nil,
                phase: .unsupported
            )
        }
    }

    public func install(
        languageTag: String
    ) async throws {
        guard downloadTask == nil else {
            throw AIProviderContractError.invalidRequest(
                "A local Speech model download is already active."
            )
        }
        let context = try await modelContext(
            languageTag: languageTag
        )
        let status = await AssetInventory.status(
            forModules: [context.transcriber]
        )
        if status == .installed {
            _ = try await AssetInventory.reserve(
                locale: context.locale
            )
            yield(
                await makeSnapshot(
                    languageTag: languageTag,
                    locale: context.locale,
                    status: .installed
                )
            )
            return
        }
        guard let request = try await AssetInventory
            .assetInstallationRequest(
                supporting: [context.transcriber]
            )
        else {
            throw AIProviderContractError.modelUnavailable(
                "The requested Apple Speech model is already managed or unavailable."
            )
        }
        self.request = request
        activeLanguageTag = languageTag
        yield(
            progressSnapshot(
                languageTag: languageTag,
                locale: context.locale,
                phase: .downloading,
                request: request
            )
        )
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(
                    for: .milliseconds(250)
                )
                await self?.publishProgress(
                    languageTag: languageTag,
                    locale: context.locale
                )
            }
        }
        let task = Task {
            try await request.downloadAndInstall()
        }
        downloadTask = task
        do {
            try await task.value
            progressTask?.cancel()
            progressTask = nil
            downloadTask = nil
            self.request = nil
            activeLanguageTag = nil
            _ = try await AssetInventory.reserve(
                locale: context.locale
            )
            let finalStatus = await AssetInventory.status(
                forModules: [context.transcriber]
            )
            guard finalStatus == .installed else {
                throw AIProviderContractError.modelUnavailable(
                    "Apple Speech did not report the model as installed."
                )
            }
            yield(
                await makeSnapshot(
                    languageTag: languageTag,
                    locale: context.locale,
                    status: finalStatus
                )
            )
        } catch {
            progressTask?.cancel()
            progressTask = nil
            downloadTask = nil
            self.request = nil
            activeLanguageTag = nil
            yield(
                LocalSpeechModelSnapshot(
                    languageTag: languageTag,
                    resolvedLocaleIdentifier:
                        context.locale.identifier(.bcp47),
                    phase: .failed
                )
            )
            throw error
        }
    }

    public func pauseDownload() {
        guard let request,
              let languageTag = activeLanguageTag
        else { return }
        request.progress.pause()
        yield(
            LocalSpeechModelSnapshot(
                languageTag: languageTag,
                resolvedLocaleIdentifier: nil,
                phase: .paused,
                completedUnitCount:
                    max(request.progress.completedUnitCount, 0),
                totalUnitCount:
                    max(request.progress.totalUnitCount, 0)
            )
        )
    }

    public func resumeDownload() {
        guard let request,
              let languageTag = activeLanguageTag
        else { return }
        request.progress.resume()
        yield(
            LocalSpeechModelSnapshot(
                languageTag: languageTag,
                resolvedLocaleIdentifier: nil,
                phase: .downloading,
                completedUnitCount:
                    max(request.progress.completedUnitCount, 0),
                totalUnitCount:
                    max(request.progress.totalUnitCount, 0)
            )
        )
    }

    public func cancelDownload() {
        request?.progress.cancel()
        downloadTask?.cancel()
        progressTask?.cancel()
        request = nil
        downloadTask = nil
        progressTask = nil
        if let languageTag = activeLanguageTag {
            yield(
                LocalSpeechModelSnapshot(
                    languageTag: languageTag,
                    resolvedLocaleIdentifier: nil,
                    phase: .supported
                )
            )
        }
        activeLanguageTag = nil
    }

    public func release(
        languageTag: String
    ) async throws {
        guard downloadTask == nil else {
            throw AIProviderContractError.invalidRequest(
                "Cancel the active model download before releasing its reservation."
            )
        }
        let context = try await modelContext(
            languageTag: languageTag
        )
        _ = await AssetInventory.release(
            reservedLocale: context.locale
        )
        yield(
            await makeSnapshot(
                languageTag: languageTag,
                locale: context.locale,
                status: await AssetInventory.status(
                    forModules: [context.transcriber]
                )
            )
        )
    }

    private func modelContext(
        languageTag: String
    ) async throws -> (
        locale: Locale,
        transcriber: SpeechTranscriber
    ) {
        let requested = Locale(identifier: languageTag)
        guard let locale = await SpeechTranscriber
            .supportedLocale(equivalentTo: requested)
        else {
            throw AIProviderContractError.modelUnavailable(
                "Apple Speech does not support the requested language."
            )
        }
        return (
            locale,
            SpeechTranscriber(
                locale: locale,
                preset:
                    .timeIndexedTranscriptionWithAlternatives
            )
        )
    }

    private func publishProgress(
        languageTag: String,
        locale: Locale
    ) {
        guard let request else { return }
        yield(
            progressSnapshot(
                languageTag: languageTag,
                locale: locale,
                phase: request.progress.isPaused
                    ? .paused
                    : .downloading,
                request: request
            )
        )
    }

    private func progressSnapshot(
        languageTag: String,
        locale: Locale,
        phase: LocalSpeechModelPhase,
        request: AssetInstallationRequest
    ) -> LocalSpeechModelSnapshot {
        LocalSpeechModelSnapshot(
            languageTag: languageTag,
            resolvedLocaleIdentifier:
                locale.identifier(.bcp47),
            phase: phase,
            completedUnitCount:
                max(request.progress.completedUnitCount, 0),
            totalUnitCount:
                max(request.progress.totalUnitCount, 0),
            isReserved: false
        )
    }

    private func makeSnapshot(
        languageTag: String,
        locale: Locale,
        status: AssetInventory.Status
    ) async -> LocalSpeechModelSnapshot {
        let phase: LocalSpeechModelPhase
        switch status {
        case .unsupported:
            phase = .unsupported
        case .supported:
            phase = .supported
        case .downloading:
            phase = .downloading
        case .installed:
            phase = .installed
        @unknown default:
            phase = .failed
        }
        let reserved = await AssetInventory.reservedLocales
            .contains {
                $0.identifier(.bcp47)
                    == locale.identifier(.bcp47)
            }
        return LocalSpeechModelSnapshot(
            languageTag: languageTag,
            resolvedLocaleIdentifier:
                locale.identifier(.bcp47),
            phase: phase,
            isReserved: reserved
        )
    }

    private func yield(
        _ snapshot: LocalSpeechModelSnapshot
    ) {
        continuation.yield(snapshot)
    }
}

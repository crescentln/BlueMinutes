import Foundation
import MeetingBuddyApplication

final class CapturePacketRelay: @unchecked Sendable {
    private struct PendingPacket {
        let packet: CapturedAudioPacket
        let durationNanoseconds: UInt64
    }

    private let sink: any CapturedAudioPacketSink
    private let trackKind: CaptureTrackKind
    private let maximumQueuedDurationNanoseconds: UInt64
    private let lock = NSLock()
    private var queue: [PendingPacket] = []
    private var queuedDurationNanoseconds: UInt64 = 0
    private var waiter: CheckedContinuation<PendingPacket?, Never>?
    private var completionWaiters: [CheckedContinuation<Void, Never>] = []
    private var admissionClosed = false
    private var failure: CaptureProviderError?
    private var worker: Task<Void, Never>?

    init(
        sink: any CapturedAudioPacketSink,
        trackKind: CaptureTrackKind,
        maximumQueuedDurationNanoseconds: UInt64
    ) {
        self.sink = sink
        self.trackKind = trackKind
        self.maximumQueuedDurationNanoseconds = maximumQueuedDurationNanoseconds
    }

    func start() {
        lock.withLock {
            guard worker == nil else { return }
            worker = Task { [weak self] in await self?.run() }
        }
    }

    @discardableResult
    func enqueue(_ packet: CapturedAudioPacket) -> Bool {
        var waiterToResume: (CheckedContinuation<PendingPacket?, Never>, PendingPacket?)?
        let accepted = lock.withLock { () -> Bool in
            guard !admissionClosed, failure == nil else { return false }
            let duration = packet.mediaRange.durationNanoseconds
            guard duration <= maximumQueuedDurationNanoseconds,
                  queuedDurationNanoseconds <= maximumQueuedDurationNanoseconds - duration
            else {
                failure = .boundedQueueExceeded(trackKind)
                admissionClosed = true
                waiterToResume = waiter.map { ($0, nil) }
                waiter = nil
                return false
            }
            let pending = PendingPacket(packet: packet, durationNanoseconds: duration)
            queuedDurationNanoseconds += duration
            if let waiter {
                waiterToResume = (waiter, pending)
                self.waiter = nil
            } else {
                queue.append(pending)
            }
            return true
        }
        if let (continuation, packet) = waiterToResume {
            continuation.resume(returning: packet)
        }
        return accepted
    }

    func fail(_ error: CaptureProviderError) {
        var waiterToResume: CheckedContinuation<PendingPacket?, Never>?
        lock.withLock {
            guard failure == nil else { return }
            failure = error
            admissionClosed = true
            waiterToResume = waiter
            waiter = nil
        }
        waiterToResume?.resume(returning: nil)
    }

    func finish() async {
        var waiterToResume: CheckedContinuation<PendingPacket?, Never>?
        lock.withLock {
            admissionClosed = true
            waiterToResume = waiter
            waiter = nil
        }
        waiterToResume?.resume(returning: nil)
        await withCheckedContinuation { continuation in
            let completeNow = lock.withLock { () -> Bool in
                if worker == nil { return true }
                completionWaiters.append(continuation)
                return false
            }
            if completeNow { continuation.resume() }
        }
    }

    private func next() async -> PendingPacket? {
        await withCheckedContinuation { continuation in
            let immediate = lock.withLock { () -> PendingPacket?? in
                if !queue.isEmpty { return .some(queue.removeFirst()) }
                if admissionClosed || failure != nil { return .some(nil) }
                waiter = continuation
                return nil
            }
            if let immediate { continuation.resume(returning: immediate) }
        }
    }

    private func run() async {
        while let pending = await next() {
            let disposition = await sink.accept(pending.packet)
            lock.withLock {
                queuedDurationNanoseconds -= pending.durationNanoseconds
                if disposition != .accepted {
                    admissionClosed = true
                    if disposition == .backpressure {
                        failure = .boundedQueueExceeded(trackKind)
                    }
                }
            }
            if disposition != .accepted { break }
        }
        let finalFailure = lock.withLock { failure }
        await sink.providerDidStop(track: trackKind, error: finalFailure)
        let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            worker = nil
            let values = completionWaiters
            completionWaiters.removeAll()
            return values
        }
        for waiter in waiters { waiter.resume() }
    }
}

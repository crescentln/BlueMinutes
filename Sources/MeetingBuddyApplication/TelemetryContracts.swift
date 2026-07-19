import Foundation
import MeetingBuddyDomain

public enum TelemetryEventName: String, Codable, Hashable, Sendable {
    case applicationStarted = "application_started"
    case workspaceHealthChecked = "workspace_health_checked"
    case taskStateChanged = "task_state_changed"
    case storageReportCalculated = "storage_report_calculated"
}

public enum TelemetryCounterKey: String, Codable, Hashable, Sendable {
    case successful = "successful"
    case failed = "failed"
    case durationBucket = "duration_bucket"
    case sizeBucket = "size_bucket"
}

public struct TelemetryCounter: Codable, Hashable, Sendable {
    public let key: TelemetryCounterKey
    public let value: UInt32

    public init(key: TelemetryCounterKey, value: UInt32) {
        self.key = key
        self.value = value
    }
}

/// Content-free by construction: there is no free-text, identifier, path,
/// filename, title, credential, meeting metadata, or payload field.
public struct ContentFreeTelemetryEvent: Codable, Hashable, Sendable {
    public let name: TelemetryEventName
    public let counters: [TelemetryCounter]

    public init(
        name: TelemetryEventName,
        counters: [TelemetryCounter] = []
    ) throws {
        let ordered = counters.sorted { $0.key.rawValue < $1.key.rawValue }
        guard ordered.count <= 8,
              Set(ordered.map(\.key)).count == ordered.count
        else {
            throw AIProviderContractError.invalidRequest(
                "Telemetry counters must use the bounded content-free schema."
            )
        }
        self.name = name
        self.counters = ordered
    }
}

public struct TelemetryPolicy: Codable, Hashable, Sendable {
    public let mode: LocalTelemetryMode
    public let noOutboundMode: Bool
    public let maximumBufferedEvents: UInt16

    public init(
        mode: LocalTelemetryMode = .disabled,
        noOutboundMode: Bool = true,
        maximumBufferedEvents: UInt16 = 256
    ) throws {
        guard mode.isKnown,
              maximumBufferedEvents > 0,
              maximumBufferedEvents <= 4_096
        else {
            throw AIProviderContractError.invalidRequest(
                "Telemetry policy bounds are invalid."
            )
        }
        self.mode = mode
        self.noOutboundMode = noOutboundMode
        self.maximumBufferedEvents = maximumBufferedEvents
    }
}

public enum TelemetryRecordDisposition: String, Codable, Hashable, Sendable {
    case suppressedDisabled = "suppressed_disabled"
    case recordedInMemory = "recorded_in_memory"
}

public protocol TelemetryRecording: Sendable {
    func record(
        _ event: ContentFreeTelemetryEvent
    ) async -> TelemetryRecordDisposition
}

/// The only Task 007 telemetry implementation is a bounded in-memory buffer.
/// It owns no URL, socket, upload, filesystem, or provider API.
public actor LocalTelemetryBuffer: TelemetryRecording {
    private let policy: TelemetryPolicy
    private var events: [ContentFreeTelemetryEvent] = []

    public init(policy: TelemetryPolicy) {
        self.policy = policy
    }

    public func record(
        _ event: ContentFreeTelemetryEvent
    ) -> TelemetryRecordDisposition {
        guard policy.mode == .localDiagnostics else { return .suppressedDisabled }
        if events.count == Int(policy.maximumBufferedEvents) {
            events.removeFirst()
        }
        events.append(event)
        return .recordedInMemory
    }

    public func bufferedEvents() -> [ContentFreeTelemetryEvent] {
        events
    }

    public func removeAll() {
        events.removeAll(keepingCapacity: false)
    }
}

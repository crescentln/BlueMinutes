import Foundation
import MeetingBuddyDomain
import OSLog

public enum BlueMinutesDiagnosticCategory:
    String,
    Codable,
    CaseIterable,
    Hashable,
    Sendable
{
    case audioCapture = "AudioCapture"
    case speechToText = "STT"
    case importFlow = "Import"
    case storage = "Storage"
    case aiProvider = "AIProvider"
    case licensing = "Licensing"
    case update = "Update"
    case windowing = "Windowing"
}

/// Stable, content-free event codes. There is deliberately no free-text,
/// identifier, title, path, URL, model response, transcript, or audio field.
public enum BlueMinutesDiagnosticEvent:
    String,
    Codable,
    CaseIterable,
    Hashable,
    Sendable
{
    case applicationStarted = "application_started"
    case mainWindowResolved = "main_window_resolved"
    case mainWindowCloseRequested = "main_window_close_requested"
    case mainWindowCloseAllowed = "main_window_close_allowed"
    case mainWindowCloseBlocked = "main_window_close_blocked"
    case mainWindowOpenRequested = "main_window_open_requested"
    case aboutWindowOpenRequested = "about_window_open_requested"
    case applicationQuitRequested = "application_quit_requested"
    case applicationTerminationRequested =
        "application_termination_requested"
    case applicationTerminationDeferred =
        "application_termination_deferred"
    case applicationTerminationAllowed =
        "application_termination_allowed"
    case applicationTerminationCancelled =
        "application_termination_cancelled"
    case sanitizedDiagnosticsCopied =
        "sanitized_diagnostics_copied"
    case mediaImportRequested = "media_import_requested"
    case recordingStartRequested =
        "recording_start_requested"
    case recordingResumeRequested =
        "recording_resume_requested"
    case recordingStopRequested =
        "recording_stop_requested"
    case speechToTextStartRequested =
        "speech_to_text_start_requested"
    case codexTurnRequested = "codex_turn_requested"
    case storageReportRequested =
        "storage_report_requested"
}

/// A local Apple Unified Logging adapter. Only a fixed event code is emitted;
/// caller-owned text and identifiers cannot be attached to the record.
public struct BlueMinutesUnifiedDiagnosticLogger: Sendable {
    private let logger: Logger

    public init(category: BlueMinutesDiagnosticCategory) {
        logger = Logger(
            subsystem: "com.meetingbuddy.desktop",
            category: category.rawValue
        )
    }

    public func record(_ event: BlueMinutesDiagnosticEvent) {
        logger.info(
            "event=\(event.rawValue, privacy: .public)"
        )
    }
}

public enum SanitizedDiagnosticsError:
    Error,
    Equatable,
    Sendable
{
    case invalidMetadata
}

/// A user-copyable diagnostic summary with no free-form application state.
/// It never accepts meeting content, identifiers, credentials, URLs, or paths.
public struct SanitizedDiagnosticsReport:
    Hashable,
    Sendable
{
    public static let schemaVersion:
        UInt32 = 1

    public let productName: String
    public let appVersion: String
    public let buildVersion: String
    public let operatingSystem: String
    public let architecture: String
    public let billingMode: BillingMode
    public let websiteMode:
        WebsiteIntegrationMode
    public let updateMode: UpdatePolicyMode
    public let telemetryMode:
        LocalTelemetryMode
    public let productFeaturesUnlocked: Bool
    public let releaseServiceRequestsPermitted:
        Bool

    public init(
        productName: String,
        appVersion: String,
        buildVersion: String,
        operatingSystem: String,
        architecture: String,
        releaseConfiguration:
            ReleaseIntegrationConfiguration,
        telemetryMode: LocalTelemetryMode
    ) throws {
        let values = [
            productName,
            appVersion,
            buildVersion,
            operatingSystem,
            architecture
        ]
        guard values.allSatisfy(
            Self.isSafeMetadataValue
        ),
            telemetryMode.isKnown
        else {
            throw SanitizedDiagnosticsError
                .invalidMetadata
        }
        self.productName = productName
        self.appVersion = appVersion
        self.buildVersion = buildVersion
        self.operatingSystem = operatingSystem
        self.architecture = architecture
        billingMode =
            releaseConfiguration.billing.mode
        websiteMode =
            releaseConfiguration.website.mode
        updateMode =
            releaseConfiguration.update.mode
        self.telemetryMode = telemetryMode
        productFeaturesUnlocked =
            releaseConfiguration.billing
            .keepsProductFeaturesUnlocked
        releaseServiceRequestsPermitted =
            releaseConfiguration.billing
            .permitsLicensingNetworkRequests
            || releaseConfiguration.website
                .permitsServiceRequests
            || releaseConfiguration.update.mode
                != .unconfigured
    }

    public var renderedText: String {
        [
            "\(productName) Sanitized Diagnostics",
            "Schema: \(Self.schemaVersion)",
            "App: \(productName) \(appVersion) (\(buildVersion))",
            "System: \(operatingSystem)",
            "Architecture: \(architecture)",
            "Product access: \(productFeaturesUnlocked ? "unlocked" : "gated")",
            "Billing: \(billingMode.rawValue)",
            "Website: \(websiteMode.rawValue)",
            "Updates: \(updateMode.rawValue)",
            "Local telemetry: \(telemetryMode.encodedValue)",
            "Release-service requests: \(releaseServiceRequestsPermitted ? "permitted" : "disabled")",
            "Meeting content included: no",
            "Transcript text included: no",
            "Audio metadata included: no",
            "Credentials or tokens included: no",
            "URLs or file paths included: no"
        ]
        .joined(separator: "\n")
    }

    private static func isSafeMetadataValue(
        _ value: String
    ) -> Bool {
        guard !value.isEmpty,
              value.utf8.count <= 160
        else { return false }
        let allowed = CharacterSet
            .alphanumerics
            .union(
                CharacterSet(
                    charactersIn:
                        " ._()-+"
                )
            )
        return value.unicodeScalars
            .allSatisfy(allowed.contains)
    }
}

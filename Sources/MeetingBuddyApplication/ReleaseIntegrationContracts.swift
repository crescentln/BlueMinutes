import Foundation

public enum BillingMode: String, Codable, Hashable, Sendable {
    case disabled
    case sandbox
    case production
}

public enum ReleaseServiceEnvironment: String, Codable, Hashable, Sendable {
    case sandbox
    case production
}

public enum ReleaseIntegrationError: Error, Equatable, Sendable {
    case buildConfigurationDenied(String)
}

/// An approval cannot be created by another target. A later distribution slice
/// must add one reviewed build-owned factory before any service can be wired.
public struct ReleaseIntegrationApproval: Sendable {
    fileprivate let environment: ReleaseServiceEnvironment
    fileprivate let updaterApproved: Bool
    fileprivate let allowedServiceEndpoints: Set<URL>
    fileprivate let allowedUpdateFeedURLs: Set<URL>

    private init(
        environment: ReleaseServiceEnvironment,
        updaterApproved: Bool,
        allowedServiceEndpoints: Set<URL>,
        allowedUpdateFeedURLs: Set<URL>
    ) {
        self.environment = environment
        self.updaterApproved = updaterApproved
        self.allowedServiceEndpoints = allowedServiceEndpoints
        self.allowedUpdateFeedURLs = allowedUpdateFeedURLs
    }

    #if DEBUG
    static func testOnly(
        environment: ReleaseServiceEnvironment,
        updaterApproved: Bool,
        allowedServiceEndpoints: Set<URL>,
        allowedUpdateFeedURLs: Set<URL>
    ) -> ReleaseIntegrationApproval {
        ReleaseIntegrationApproval(
            environment: environment,
            updaterApproved: updaterApproved,
            allowedServiceEndpoints: allowedServiceEndpoints,
            allowedUpdateFeedURLs: allowedUpdateFeedURLs
        )
    }
    #endif
}

public struct BillingFeatureGate: Hashable, Sendable {
    public let mode: BillingMode

    private init(mode: BillingMode) {
        self.mode = mode
    }

    public var keepsProductFeaturesUnlocked: Bool {
        mode == .disabled
    }

    public var permitsLicensingNetworkRequests: Bool {
        mode != .disabled
    }

    public var displaysTrialOrPaywall: Bool {
        mode != .disabled
    }

    public static let publicBeta = BillingFeatureGate(mode: .disabled)

    public static func internalSandbox(
        approval: ReleaseIntegrationApproval
    ) throws -> BillingFeatureGate {
        guard approval.environment == .sandbox else {
            throw ReleaseIntegrationError.buildConfigurationDenied(
                "Sandbox billing requires a sandbox build approval."
            )
        }
        return BillingFeatureGate(mode: .sandbox)
    }
}

public enum WebsiteIntegrationMode: String, Codable, Hashable, Sendable {
    case disconnected
    case publicLinksOnly = "public_links_only"
    case services
}

/// App-side handoff for the separately developed website. The default contains
/// no endpoint and cannot perform a network request.
public struct WebsiteIntegrationConfiguration: Hashable, Sendable {
    public let mode: WebsiteIntegrationMode
    public let serviceEnvironment: ReleaseServiceEnvironment?
    public let publicWebsiteURL: URL?
    public let supportURL: URL?
    public let privacyURL: URL?
    public let updateFeedURL: URL?
    public let billingAPIBaseURL: URL?

    private init(
        mode: WebsiteIntegrationMode,
        serviceEnvironment: ReleaseServiceEnvironment?,
        publicWebsiteURL: URL?,
        supportURL: URL?,
        privacyURL: URL?,
        updateFeedURL: URL?,
        billingAPIBaseURL: URL?
    ) {
        self.mode = mode
        self.serviceEnvironment = serviceEnvironment
        self.publicWebsiteURL = publicWebsiteURL
        self.supportURL = supportURL
        self.privacyURL = privacyURL
        self.updateFeedURL = updateFeedURL
        self.billingAPIBaseURL = billingAPIBaseURL
    }

    public static let disconnected = WebsiteIntegrationConfiguration(
        mode: .disconnected,
        serviceEnvironment: nil,
        publicWebsiteURL: nil,
        supportURL: nil,
        privacyURL: nil,
        updateFeedURL: nil,
        billingAPIBaseURL: nil
    )

    public static func publicLinks(
        publicWebsiteURL: URL? = nil,
        supportURL: URL? = nil,
        privacyURL: URL? = nil
    ) throws -> WebsiteIntegrationConfiguration {
        let urls = [publicWebsiteURL, supportURL, privacyURL].compactMap { $0 }
        guard !urls.isEmpty,
              urls.allSatisfy(Self.isSyntacticallyConstrainedHTTPSURL)
        else {
            throw ReleaseIntegrationError.buildConfigurationDenied(
                "Public website links require at least one syntactically constrained HTTPS URL."
            )
        }
        return WebsiteIntegrationConfiguration(
            mode: .publicLinksOnly,
            serviceEnvironment: nil,
            publicWebsiteURL: publicWebsiteURL,
            supportURL: supportURL,
            privacyURL: privacyURL,
            updateFeedURL: nil,
            billingAPIBaseURL: nil
        )
    }

    public static func approvedServices(
        environment: ReleaseServiceEnvironment,
        publicWebsiteURL: URL? = nil,
        supportURL: URL? = nil,
        privacyURL: URL? = nil,
        updateFeedURL: URL? = nil,
        billingAPIBaseURL: URL? = nil,
        approval: ReleaseIntegrationApproval
    ) throws -> WebsiteIntegrationConfiguration {
        let urls = [
            publicWebsiteURL,
            supportURL,
            privacyURL,
            updateFeedURL,
            billingAPIBaseURL
        ].compactMap { $0 }
        let serviceURLs = [updateFeedURL, billingAPIBaseURL].compactMap { $0 }
        let updateFeedIsApproved = updateFeedURL.map {
            approval.updaterApproved
                && approval.allowedUpdateFeedURLs.contains($0)
        } ?? true
        guard approval.environment == environment,
              !serviceURLs.isEmpty,
              urls.allSatisfy(Self.isSyntacticallyConstrainedHTTPSURL),
              serviceURLs.allSatisfy(
                  approval.allowedServiceEndpoints.contains
              ),
              updateFeedIsApproved
        else {
            throw ReleaseIntegrationError.buildConfigurationDenied(
                "Website services require matching build environment and allowlisted, syntactically constrained HTTPS endpoints."
            )
        }
        return WebsiteIntegrationConfiguration(
            mode: .services,
            serviceEnvironment: environment,
            publicWebsiteURL: publicWebsiteURL,
            supportURL: supportURL,
            privacyURL: privacyURL,
            updateFeedURL: updateFeedURL,
            billingAPIBaseURL: billingAPIBaseURL
        )
    }

    public var permitsServiceRequests: Bool {
        mode == .services
            && serviceEnvironment != nil
            && (updateFeedURL != nil || billingAPIBaseURL != nil)
    }

    fileprivate static func isSyntacticallyConstrainedHTTPSURL(
        _ url: URL
    ) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host,
              !host.isEmpty,
              url.user == nil,
              url.password == nil,
              url.fragment == nil
        else {
            return false
        }
        return true
    }
}

public enum UpdatePolicyMode: String, Codable, Hashable, Sendable {
    case unconfigured
    case manual
    case automatic
}

public struct UpdatePolicy: Hashable, Sendable {
    public let mode: UpdatePolicyMode
    public let serviceEnvironment: ReleaseServiceEnvironment?
    public let feedURL: URL?

    private init(
        mode: UpdatePolicyMode,
        serviceEnvironment: ReleaseServiceEnvironment?,
        feedURL: URL?
    ) {
        self.mode = mode
        self.serviceEnvironment = serviceEnvironment
        self.feedURL = feedURL
    }

    public static let publicBeta = UpdatePolicy(
        mode: .unconfigured,
        serviceEnvironment: nil,
        feedURL: nil
    )

    public static func approved(
        mode: UpdatePolicyMode,
        environment: ReleaseServiceEnvironment,
        feedURL: URL,
        approval: ReleaseIntegrationApproval
    ) throws -> UpdatePolicy {
        guard mode != .unconfigured,
              approval.environment == environment,
              approval.updaterApproved,
              WebsiteIntegrationConfiguration
                  .isSyntacticallyConstrainedHTTPSURL(feedURL),
              approval.allowedUpdateFeedURLs.contains(feedURL),
              approval.allowedServiceEndpoints.contains(feedURL)
        else {
            throw ReleaseIntegrationError.buildConfigurationDenied(
                "Configured updates require a matching approved build and an HTTPS feed in both exact update and service-endpoint allowlists."
            )
        }
        return UpdatePolicy(
            mode: mode,
            serviceEnvironment: environment,
            feedURL: feedURL
        )
    }
}

public struct ReleaseIntegrationConfiguration: Hashable, Sendable {
    public let billing: BillingFeatureGate
    public let website: WebsiteIntegrationConfiguration
    public let update: UpdatePolicy

    private init(
        billing: BillingFeatureGate,
        website: WebsiteIntegrationConfiguration,
        update: UpdatePolicy
    ) {
        self.billing = billing
        self.website = website
        self.update = update
    }

    public static let publicBeta = ReleaseIntegrationConfiguration(
        billing: .publicBeta,
        website: .disconnected,
        update: .publicBeta
    )

    public static func approvedInternal(
        billing: BillingFeatureGate,
        website: WebsiteIntegrationConfiguration,
        update: UpdatePolicy,
        approval: ReleaseIntegrationApproval
    ) throws -> ReleaseIntegrationConfiguration {
        let serviceEndpoints = [
            website.updateFeedURL,
            website.billingAPIBaseURL
        ].compactMap { $0 }
        let updateFeedIsCoherent = website.updateFeedURL == update.feedURL
            && (
                update.mode == .unconfigured
                    ? update.feedURL == nil
                    : update.feedURL != nil
            )
        let currentApprovalOwnsServices = serviceEndpoints.allSatisfy(
            approval.allowedServiceEndpoints.contains
        )
        let currentApprovalOwnsUpdate = update.feedURL.map {
            approval.updaterApproved
                && approval.allowedUpdateFeedURLs.contains($0)
                && approval.allowedServiceEndpoints.contains($0)
        } ?? true
        guard billing.mode != .production,
              website.serviceEnvironment.map({ $0 == approval.environment }) ?? true,
              update.serviceEnvironment.map({ $0 == approval.environment }) ?? true,
              updateFeedIsCoherent,
              currentApprovalOwnsServices,
              currentApprovalOwnsUpdate,
              billing.mode != .disabled || website.billingAPIBaseURL == nil,
              billing.mode != .sandbox
                  || (
                      approval.environment == .sandbox
                          && website.serviceEnvironment != .production
                  )
        else {
            throw ReleaseIntegrationError.buildConfigurationDenied(
                "Billing, website, and update configuration do not share one approved release environment."
            )
        }
        return ReleaseIntegrationConfiguration(
            billing: billing,
            website: website,
            update: update
        )
    }
}

public enum UpdateAction: String, Codable, Hashable, Sendable {
    case check
    case download
    case install
}

public enum UpdateActionDecision: Hashable, Sendable {
    case allowed
    case blocked(reasonCode: String)
}

public struct UpdateSafetyGate: Sendable {
    public init() {}

    public func decide(
        _ action: UpdateAction,
        configuration: ReleaseIntegrationConfiguration,
        activeMeeting: Bool
    ) -> UpdateActionDecision {
        let policy = configuration.update
        let website = configuration.website
        guard policy.mode != .unconfigured,
              policy.serviceEnvironment != nil,
              policy.feedURL != nil,
              website.mode == .services,
              website.permitsServiceRequests,
              website.serviceEnvironment == policy.serviceEnvironment,
              website.updateFeedURL == policy.feedURL
        else {
            return .blocked(reasonCode: "update_service_unconfigured")
        }
        if activeMeeting, action != .check {
            return .blocked(reasonCode: "active_meeting_protects_runtime")
        }
        return .allowed
    }
}

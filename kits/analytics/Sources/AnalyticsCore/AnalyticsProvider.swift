import Foundation

/// A backend that receives validated, redacted events. Apps register zero or
/// more providers with `AnalyticsClient`. Real network providers (TelemetryDeck,
/// PostHog, a first-party Supabase table, ...) conform to this from the
/// product repo; this package only ships the network-free ones below.
public protocol AnalyticsProvider {
    var identifier: String { get }
    func track(_ event: AnalyticsEvent)
}

/// Sends nowhere. Used when analytics is disabled or unconfigured so the
/// facade never has to special-case "no provider".
public final class AnalyticsNoopProvider: AnalyticsProvider {
    public let identifier = "noop"
    public init() {}
    public func track(_ event: AnalyticsEvent) {}
}

import Foundation

/// The facade every product's `<Product>Analytics` wraps. Construct with
/// whatever providers are configured (typically `[AnalyticsDebugSink()]` until
/// a real backend is wired in, or `[]`/`[AnalyticsNoopProvider()]` when the
/// user has opted out) and call `log(_:params:)` from view code.
///
/// Invalid event/param names never reach a provider (they're only surfaced
/// via `onInvalidEvent` so tests/QA can catch mistakes) — this keeps the
/// naming convention in docs/ANALYTICS.md actually enforced, not just documented.
public final class AnalyticsClient {
    private let providers: [AnalyticsProvider]
    private let isEnabled: Bool
    private let redactPII: Bool
    private let onInvalidEvent: ((String) -> Void)?

    public init(
        providers: [AnalyticsProvider],
        isEnabled: Bool = true,
        redactPII: Bool = true,
        onInvalidEvent: ((String) -> Void)? = nil
    ) {
        self.providers = providers
        self.isEnabled = isEnabled
        self.redactPII = redactPII
        self.onInvalidEvent = onInvalidEvent
    }

    @discardableResult
    public func log(_ name: String, params: [String: AnalyticsValue] = [:]) -> Bool {
        guard isEnabled else { return false }
        guard AnalyticsEventNaming.isValidEventName(name) else {
            onInvalidEvent?("invalid event name: \(name)")
            return false
        }
        for key in params.keys where !AnalyticsEventNaming.isValidParamKey(key) {
            onInvalidEvent?("invalid param key: \(key) on event \(name)")
        }
        let cleanParams = redactPII ? AnalyticsPrivacy.redactingLikelyPII(from: params) : params
        let event = AnalyticsEvent(name: name, params: cleanParams)
        for provider in providers {
            provider.track(event)
        }
        return true
    }
}

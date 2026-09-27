import Foundation

/// Best-effort, defense-in-depth heuristics that catch obviously-identifying
/// values before they reach any provider. This is NOT a substitute for
/// choosing non-identifying param values in the first place — see
/// docs/ANALYTICS.md's privacy checklist — but it stops an accidental
/// `email` or raw name from silently leaving the device.
public enum AnalyticsPrivacy {
    private static let emailPattern = try! NSRegularExpression(
        pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
    )
    /// 7+ consecutive digits (ignoring separators) reads as a phone number, account number, etc.
    private static let longDigitRunPattern = try! NSRegularExpression(pattern: #"(?:\d[\s.-]?){7,}"#)

    /// Param keys that are always dropped outright, regardless of value shape —
    /// these names alone signal PII intent.
    public static let blockedParamKeys: Set<String> = [
        "email", "phone", "full_name", "name", "address", "ssn", "password",
        "apple_id", "device_token", "auth_token", "access_token"
    ]

    public static func containsLikelyPII(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        if emailPattern.firstMatch(in: value, range: range) != nil { return true }
        if longDigitRunPattern.firstMatch(in: value, range: range) != nil { return true }
        return false
    }

    /// Drops blocked keys entirely and redacts string values that look like PII in place
    /// (keeps the key so counts/shape are still visible in the debug sink, but never the value).
    public static func redactingLikelyPII(from params: [String: AnalyticsValue]) -> [String: AnalyticsValue] {
        var cleaned: [String: AnalyticsValue] = [:]
        for (key, value) in params {
            let lowerKey = key.lowercased()
            if blockedParamKeys.contains(lowerKey) {
                continue
            }
            if case .string(let s) = value, containsLikelyPII(s) {
                cleaned[key] = .string("[redacted]")
                continue
            }
            cleaned[key] = value
        }
        return cleaned
    }
}

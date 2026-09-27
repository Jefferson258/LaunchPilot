import Foundation

/// A single analytics event. Keep params small and non-identifying — see
/// docs/ANALYTICS.md for the privacy checklist (no email/name/exact location/
/// free-text user content).
public struct AnalyticsEvent: Equatable, Codable {
    public let name: String
    public let params: [String: AnalyticsValue]
    public let timestamp: Date

    public init(name: String, params: [String: AnalyticsValue] = [:], timestamp: Date = Date()) {
        self.name = name
        self.params = params
        self.timestamp = timestamp
    }
}

/// JSON-safe scalar param value. Deliberately narrow (no nested objects/arrays)
/// so events stay flat, small, and easy to redact.
public enum AnalyticsValue: Equatable, Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    public var stringValue: String {
        switch self {
        case .string(let v): return v
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .bool(let v): return String(v)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Int.self) { self = .int(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported AnalyticsValue")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        }
    }
}

extension AnalyticsValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral, ExpressibleByFloatLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
}

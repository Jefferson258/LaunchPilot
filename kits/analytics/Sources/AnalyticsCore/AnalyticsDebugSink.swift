import Foundation
import os

/// Records events without any network access, so analytics is testable
/// today, before any provider account/app-id exists:
///  - keeps the last `maxBufferedEvents` in memory (`recordedEvents`) for
///    unit tests / QA / an on-screen debug overlay to inspect directly,
///  - optionally appends each event as one JSON line to a local file (never
///    uploaded anywhere) so a human or a UI test can verify events fired on
///    a real device/simulator after the process exits,
///  - os.Logger + optional console print when `logToConsole` is true.
///
/// This is deliberately the *default* provider for every product until a
/// real backend is wired in — see docs/ANALYTICS.md.
public final class AnalyticsDebugSink: AnalyticsProvider {
    public let identifier = "debug"

    private let maxBufferedEvents: Int
    private let fileURL: URL?
    private let logToConsole: Bool
    private let logger: Logger

    private let lock = NSLock()
    private var buffer: [AnalyticsEvent] = []

    public init(
        maxBufferedEvents: Int = 200,
        fileURL: URL? = nil,
        logToConsole: Bool = true,
        loggerSubsystem: String = "com.launchpilot.analytics"
    ) {
        self.maxBufferedEvents = max(1, maxBufferedEvents)
        self.fileURL = fileURL
        self.logToConsole = logToConsole
        self.logger = Logger(subsystem: loggerSubsystem, category: "AnalyticsDebug")
    }

    public func track(_ event: AnalyticsEvent) {
        lock.lock()
        buffer.append(event)
        if buffer.count > maxBufferedEvents {
            buffer.removeFirst(buffer.count - maxBufferedEvents)
        }
        lock.unlock()

        let paramsDescription = event.params
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.stringValue)" }
            .joined(separator: " ")

        if logToConsole {
            if paramsDescription.isEmpty {
                logger.debug("\(event.name, privacy: .public)")
                print("[Analytics][debug] \(event.name)")
            } else {
                logger.debug("\(event.name, privacy: .public) \(paramsDescription, privacy: .public)")
                print("[Analytics][debug] \(event.name) \(paramsDescription)")
            }
        }

        appendToFileIfConfigured(event)
    }

    /// Thread-safe snapshot of everything currently buffered (oldest first).
    public var recordedEvents: [AnalyticsEvent] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    public var eventCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }

    public func clear() {
        lock.lock()
        buffer.removeAll()
        lock.unlock()
    }

    // MARK: - File sink (best-effort; never throws into caller)

    private func appendToFileIfConfigured(_ event: AnalyticsEvent) {
        guard let fileURL else { return }
        guard let line = Self.jsonLine(for: event) else { return }
        let data = (line + "\n").data(using: .utf8) ?? Data()

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        handle.write(data)
    }

    private static let iso8601 = ISO8601DateFormatter()

    static func jsonLine(for event: AnalyticsEvent) -> String? {
        var payload: [String: Any] = [
            "name": event.name,
            "timestamp": iso8601.string(from: event.timestamp)
        ]
        var paramsJSON: [String: Any] = [:]
        for (key, value) in event.params {
            switch value {
            case .string(let v): paramsJSON[key] = v
            case .int(let v): paramsJSON[key] = v
            case .double(let v): paramsJSON[key] = v
            case .bool(let v): paramsJSON[key] = v
            }
        }
        payload["params"] = paramsJSON
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

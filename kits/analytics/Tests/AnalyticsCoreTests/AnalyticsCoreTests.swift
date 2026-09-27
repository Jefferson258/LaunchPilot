import XCTest
@testable import AnalyticsCore

final class AnalyticsCoreTests: XCTestCase {

    // MARK: - Naming

    func testEventNameValidation_acceptsSnakeCase() {
        for name in ["app_open", "tab_view", "sign_in", "screen_view", "ab"] {
            XCTAssertTrue(AnalyticsEventNaming.isValidEventName(name), "\(name) should be valid")
        }
    }

    func testEventNameValidation_rejectsBadNames() {
        for name in ["AppOpen", "app open", "app-open", "1app", "a", "", String(repeating: "a", count: 41)] {
            XCTAssertFalse(AnalyticsEventNaming.isValidEventName(name), "\(name) should be invalid")
        }
    }

    // MARK: - Privacy redaction

    func testPIIRedaction_dropsBlockedKeys() {
        let params: [String: AnalyticsValue] = ["email": "user@example.com", "method": "apple"]
        let cleaned = AnalyticsPrivacy.redactingLikelyPII(from: params)
        XCTAssertNil(cleaned["email"])
        XCTAssertEqual(cleaned["method"], .string("apple"))
    }

    func testPIIRedaction_redactsEmailLikeStringValues() {
        let params: [String: AnalyticsValue] = ["note": "contact me at user@example.com"]
        let cleaned = AnalyticsPrivacy.redactingLikelyPII(from: params)
        XCTAssertEqual(cleaned["note"], .string("[redacted]"))
    }

    func testPIIRedaction_leavesNonPIIValuesAlone() {
        let params: [String: AnalyticsValue] = ["tab": "dashboard", "index": 2, "is_first_launch": true]
        let cleaned = AnalyticsPrivacy.redactingLikelyPII(from: params)
        XCTAssertEqual(cleaned["tab"], .string("dashboard"))
        XCTAssertEqual(cleaned["index"], .int(2))
        XCTAssertEqual(cleaned["is_first_launch"], .bool(true))
    }

    // MARK: - Debug sink

    func testDebugSinkRingBufferCapsAtMax() {
        let sink = AnalyticsDebugSink(maxBufferedEvents: 3, logToConsole: false)
        for i in 0..<10 {
            sink.track(AnalyticsEvent(name: "app_open", params: ["i": .int(i)]))
        }
        XCTAssertEqual(sink.eventCount, 3)
        XCTAssertEqual(sink.recordedEvents.map(\.params["i"]), [.int(7), .int(8), .int(9)])
    }

    func testDebugSinkClear() {
        let sink = AnalyticsDebugSink(logToConsole: false)
        sink.track(AnalyticsEvent(name: "app_open"))
        XCTAssertEqual(sink.eventCount, 1)
        sink.clear()
        XCTAssertEqual(sink.eventCount, 0)
    }

    func testDebugSinkWritesValidJSONLFile() throws {
        let dir = FileManager.default.temporaryDirectory
        let fileURL = dir.appendingPathComponent("analytics-test-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let sink = AnalyticsDebugSink(fileURL: fileURL, logToConsole: false)
        sink.track(AnalyticsEvent(name: "app_open", params: ["source": "cold_start"]))
        sink.track(AnalyticsEvent(name: "tab_view", params: ["tab": "dashboard", "index": 1]))

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = contents.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2)
        for line in lines {
            let data = Data(line.utf8)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            XCTAssertNotNil(json?["name"])
            XCTAssertNotNil(json?["timestamp"])
            XCTAssertNotNil(json?["params"])
        }
        XCTAssertTrue(lines[0].contains("app_open"))
        XCTAssertTrue(lines[1].contains("tab_view"))
    }

    // MARK: - Client

    func testAnalyticsClientDispatchesToAllProviders() {
        let sinkA = AnalyticsDebugSink(logToConsole: false)
        let sinkB = AnalyticsDebugSink(logToConsole: false)
        let client = AnalyticsClient(providers: [sinkA, sinkB])

        XCTAssertTrue(client.log("app_open", params: ["source": "cold_start"]))

        XCTAssertEqual(sinkA.eventCount, 1)
        XCTAssertEqual(sinkB.eventCount, 1)
        XCTAssertEqual(sinkA.recordedEvents.first?.name, "app_open")
    }

    func testAnalyticsClientRejectsInvalidEventName() {
        let sink = AnalyticsDebugSink(logToConsole: false)
        var invalidMessages: [String] = []
        let client = AnalyticsClient(providers: [sink], onInvalidEvent: { invalidMessages.append($0) })

        let accepted = client.log("App Open")

        XCTAssertFalse(accepted)
        XCTAssertEqual(sink.eventCount, 0)
        XCTAssertEqual(invalidMessages.count, 1)
    }

    func testAnalyticsClientNoopWhenDisabled() {
        let sink = AnalyticsDebugSink(logToConsole: false)
        let client = AnalyticsClient(providers: [sink], isEnabled: false)

        XCTAssertFalse(client.log("app_open"))
        XCTAssertEqual(sink.eventCount, 0)
    }

    func testAnalyticsClientRedactsPIIBeforeReachingProvider() {
        let sink = AnalyticsDebugSink(logToConsole: false)
        let client = AnalyticsClient(providers: [sink])

        client.log("sign_in", params: ["method": "apple", "email": "user@example.com"])

        let event = sink.recordedEvents.first
        XCTAssertNil(event?.params["email"])
        XCTAssertEqual(event?.params["method"], .string("apple"))
    }

    func testNoopProviderNeverThrowsAndRecordsNothingObservable() {
        let provider = AnalyticsNoopProvider()
        let client = AnalyticsClient(providers: [provider])
        XCTAssertTrue(client.log("app_open"))
    }
}

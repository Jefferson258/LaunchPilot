// swift-tools-version: 5.9
import PackageDescription

// AnalyticsCore is the canonical, tested reference implementation of the
// LaunchPilot analytics pattern: an event model, event-name/param validation,
// a lightweight PII-redaction heuristic, and a no-network "debug sink" that
// records events to memory (+ optionally a local JSONL file) for QA.
//
// It has zero UIKit/SwiftUI/network dependencies on purpose, so it can be
// unit-tested with `swift test` on any machine (no simulator, no Xcode
// project needed) and so its logic can be read/ported 1:1 into each product
// app's own AnalyticsClient (see docs/ANALYTICS.md for why we copy rather
// than add a cross-repo SPM dependency to each Xcode project).
let package = Package(
    name: "AnalyticsCore",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "AnalyticsCore", targets: ["AnalyticsCore"])
    ],
    targets: [
        .target(name: "AnalyticsCore"),
        .testTarget(name: "AnalyticsCoreTests", dependencies: ["AnalyticsCore"])
    ]
)

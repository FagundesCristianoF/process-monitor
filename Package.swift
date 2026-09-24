// swift-tools-version: 5.9
import PackageDescription

// Full strict-concurrency checking (the Swift 6 data-race diagnostics) as warnings,
// so the code stays ready for the Swift 6 language mode.
let strictConcurrency: [SwiftSetting] = [.enableUpcomingFeature("StrictConcurrency")]

let package = Package(
    name: "ProcessMonitor",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.36.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "ProcessMonitor",
            dependencies: [
                .product(name: "Sentry", package: "sentry-cocoa"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "ProcessMonitor",
            resources: [.process("Resources")],
            swiftSettings: strictConcurrency,
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "ProcessMonitorTests",
            dependencies: ["ProcessMonitor"],
            path: "Tests/ProcessMonitorTests",
            swiftSettings: strictConcurrency
        )
    ]
)

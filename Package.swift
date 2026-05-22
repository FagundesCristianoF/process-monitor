// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProcessMonitor",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.36.0")
    ],
    targets: [
        .executableTarget(
            name: "ProcessMonitor",
            dependencies: [
                .product(name: "Sentry", package: "sentry-cocoa")
            ],
            path: "ProcessMonitor",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ProcessMonitorTests",
            dependencies: ["ProcessMonitor"],
            path: "Tests/ProcessMonitorTests"
        )
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProcessMonitor",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ProcessMonitor",
            path: "ProcessMonitor"
        )
    ]
)

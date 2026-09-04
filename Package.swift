// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "trace-mem",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "TraceMem",
            path: "Sources/TraceMem",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(name: "TraceMemTests", dependencies: ["TraceMem"]),
    ]
)

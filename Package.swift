// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodexAudioMonitor",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "CodexAudioCore",
            targets: ["CodexAudioCore"]
        ),
        .executable(
            name: "CodexAudioMonitor",
            targets: ["CodexAudioMonitor"]
        ),
        .executable(
            name: "CodexAudioBridge",
            targets: ["CodexAudioBridge"]
        )
    ],
    targets: [
        .target(
            name: "CodexAudioCore",
            path: "Sources/CodexAudioMonitor/Core",
            exclude: ["Codex"],
            sources: ["Audio", "Bridge"]
        ),
        .executableTarget(
            name: "CodexAudioMonitor",
            dependencies: ["CodexAudioCore"],
            path: "Sources/CodexAudioMonitor",
            exclude: ["Core/Audio", "Core/Bridge"]
        ),
        .executableTarget(
            name: "CodexAudioBridge",
            dependencies: ["CodexAudioCore"],
            path: "Sources/CodexAudioBridge"
        ),
        .testTarget(
            name: "CodexAudioMonitorTests",
            dependencies: ["CodexAudioMonitor", "CodexAudioCore"]
        )
    ]
)

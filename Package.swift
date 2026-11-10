// swift-tools-version: 6.2
import PackageDescription

// Everything runs on the main actor unless it says otherwise: the app is AppKit UI plus a
// trackpad listener whose sensor thread hands every frame to the main thread.
let settings: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "TrackpadEdge",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "TrackpadEdge",
            path: "Sources/TrackpadEdge",
            swiftSettings: settings
        ),
        .testTarget(
            name: "TrackpadEdgeTests",
            dependencies: ["TrackpadEdge"],
            path: "Tests/TrackpadEdgeTests",
            swiftSettings: settings
        ),
    ]
)

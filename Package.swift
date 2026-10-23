// swift-tools-version: 6.0
//
// A small macOS client for the personal-intelligence service ("intel").
// It shows what the `intel` CLI shows, through the HTTP API the background service serves.
//
//   IntelKit   models + HTTP client + connection settings (no UI; unit-tested)
//   Intel      the SwiftUI app
//
// Open this folder in Xcode to run it, or build an app bundle with scripts/build_app.sh.

import PackageDescription

let package = Package(
    name: "IntelGUI",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Intel", targets: ["Intel"]),
        .library(name: "IntelKit", targets: ["IntelKit"]),
    ],
    targets: [
        .target(name: "IntelKit", path: "Sources/IntelKit"),
        .executableTarget(name: "Intel", dependencies: ["IntelKit"], path: "Sources/Intel"),
        .testTarget(
            name: "IntelKitTests",
            dependencies: ["IntelKit"],
            path: "Tests/IntelKitTests",
            resources: [.copy("Samples")]
        ),
    ]
)

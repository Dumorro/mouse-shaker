// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MouseShaker",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MouseShaker", targets: ["MouseShaker"]),
    ],
    targets: [
        // Pure logic (settings, schedule, state machine, motion paths). No AppKit, fully unit-tested.
        .target(name: "ShakerCore"),
        // Menu bar app: event synthesis, system monitors, SwiftUI.
        .executableTarget(
            name: "MouseShaker",
            dependencies: ["ShakerCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "ShakerCoreTests", dependencies: ["ShakerCore"]),
    ]
)

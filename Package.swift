// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InvisibleMessenger",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "InvisibleMessenger", targets: ["InvisibleMessenger"]),
    ],
    targets: [
        .target(
            name: "MessengerCore",
            linkerSettings: [.linkedFramework("Network")]
        ),
        .target(
            name: "InvisibleMessengerKit",
            dependencies: ["MessengerCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(
            name: "InvisibleMessenger",
            dependencies: ["InvisibleMessengerKit"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        /// Drives the real UI (two copies of the app on loopback) through every flow: scripts/ui-tests.sh
        .executableTarget(
            name: "UIFlowRunner",
            dependencies: ["InvisibleMessengerKit", "MessengerCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "MessengerCoreTests",
            dependencies: ["MessengerCore"]
        ),
        .testTarget(
            name: "InvisibleMessengerTests",
            dependencies: ["InvisibleMessengerKit", "MessengerCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)

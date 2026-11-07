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
        .executableTarget(
            name: "InvisibleMessenger",
            dependencies: ["MessengerCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "MessengerCoreTests",
            dependencies: ["MessengerCore"]
        ),
    ]
)

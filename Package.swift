// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Centauri",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Centauri", targets: ["CentauriApp"]),
        .executable(name: "centauri-cli", targets: ["CentauriCLI"])
    ],
    targets: [
        .target(name: "CentauriCore"),
        .executableTarget(name: "CentauriApp", dependencies: ["CentauriCore"]),
        .executableTarget(name: "CentauriCLI", dependencies: ["CentauriCore"]),
        .testTarget(name: "CentauriCoreTests", dependencies: ["CentauriCore"])
    ]
)

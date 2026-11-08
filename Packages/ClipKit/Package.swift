// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClipKit",
    platforms: [.macOS(.v13), .iOS(.v26)],
    products: [
        .library(name: "ClipKit", targets: ["ClipKit"]),
    ],
    dependencies: [
        .package(path: "../VaultKit"),
    ],
    targets: [
        .target(name: "ClipKit", dependencies: ["VaultKit"], resources: [.copy("Scripts")]),
        .testTarget(name: "ClipKitTests", dependencies: ["ClipKit"]),
    ]
)

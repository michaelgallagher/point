// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VaultKit",
    platforms: [.macOS(.v13), .iOS(.v26)],
    products: [
        .library(name: "VaultKit", targets: ["VaultKit"]),
    ],
    dependencies: [
        .package(path: "../MarkdownKit"),
    ],
    targets: [
        .target(name: "VaultKit", dependencies: ["MarkdownKit"]),
        .testTarget(name: "VaultKitTests", dependencies: ["VaultKit"]),
    ]
)

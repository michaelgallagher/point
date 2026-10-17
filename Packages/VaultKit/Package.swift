// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VaultKit",
    platforms: [.macOS(.v13), .iOS(.v26)],
    products: [
        .library(name: "VaultKit", targets: ["VaultKit"]),
    ],
    targets: [
        .target(name: "VaultKit"),
        .testTarget(name: "VaultKitTests", dependencies: ["VaultKit"]),
    ]
)

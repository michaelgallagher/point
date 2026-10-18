// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "IndexKit",
    platforms: [.macOS(.v13), .iOS(.v26)],
    products: [
        .library(name: "IndexKit", targets: ["IndexKit"]),
    ],
    dependencies: [
        .package(path: "../VaultKit"),
        .package(path: "../MarkdownKit"),
    ],
    targets: [
        .target(name: "IndexKit", dependencies: ["VaultKit", "MarkdownKit"], linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "IndexKitTests", dependencies: ["IndexKit"]),
    ]
)

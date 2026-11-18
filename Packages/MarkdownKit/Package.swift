// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MarkdownKit",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "MarkdownKit", targets: ["MarkdownKit"]),
    ],
    targets: [
        .target(name: "MarkdownKit"),
        .testTarget(name: "MarkdownKitTests", dependencies: ["MarkdownKit"]),
    ]
)

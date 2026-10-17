// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EditorKit",
    platforms: [.macOS(.v13), .iOS(.v26)],
    products: [
        .library(name: "EditorKit", targets: ["EditorKit"]),
    ],
    dependencies: [
        .package(path: "../MarkdownKit"),
    ],
    targets: [
        .target(name: "EditorKit", dependencies: ["MarkdownKit"]),
        .testTarget(name: "EditorKitTests", dependencies: ["EditorKit", "MarkdownKit"]),
    ]
)

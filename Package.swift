// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MarkdownMe",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MarkdownCore", targets: ["MarkdownCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.9.0"),
    ],
    targets: [
        // Pure logic, never AppKit or SwiftUI, so it builds and tests on Linux
        // as well as macOS.
        .target(
            name: "MarkdownCore",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")]
        ),
        .testTarget(
            name: "MarkdownCoreTests",
            dependencies: ["MarkdownCore"]
        ),
    ]
)

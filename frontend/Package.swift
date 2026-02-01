// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Anchor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Anchor", targets: ["Anchor"])
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.3.0")
    ],
    targets: [
        .executableTarget(
            name: "Anchor",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "AnchorTests",
            dependencies: ["Anchor"],
            path: "Tests"
        )
    ]
)

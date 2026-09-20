// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OpenClipText",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .executableTarget(
            name: "OpenClipText",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            path: "Sources/OpenClipText"
        ),
        .testTarget(
            name: "OpenClipTextTests",
            dependencies: ["OpenClipText"],
            path: "Tests/OpenClipTextTests"
        )
    ]
)
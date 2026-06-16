// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SmartLinksOpener",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SmartLinksOpener",
            path: "Sources/SmartLinksOpener"
        ),
        .testTarget(
            name: "SmartLinksOpenerTests",
            dependencies: ["SmartLinksOpener"],
            path: "Tests/SmartLinksOpenerTests"
        ),
    ]
)

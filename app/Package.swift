// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PingMenubar",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "PingIcon",
            path: "Sources/PingIcon"
        ),
        .target(
            name: "TestKit",
            path: "Sources/TestKit"
        ),
        .target(
            name: "PingMenubarApp",
            dependencies: ["PingIcon"],
            path: "Sources/PingMenubarApp"
        ),
        .executableTarget(
            name: "PingMenubar",
            dependencies: ["PingMenubarApp"],
            path: "Sources/PingMenubar"
        ),
        .executableTarget(
            name: "IconExport",
            dependencies: ["PingIcon"],
            path: "Sources/IconExport"
        ),
        .executableTarget(
            name: "PingMenubarTests",
            dependencies: ["PingMenubarApp", "TestKit"],
            path: "Tests/PingMenubarAppTests"
        ),
    ]
)

// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GTDPlanner",
    // Liquid Glass is a macOS 26 API. The standalone app intentionally
    // targets Tahoe so the UI can use the native material instead of a
    // compatibility approximation.
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "GTDPlanner", targets: ["GTDPlanner"])
    ],
    targets: [
        .executableTarget(
            name: "GTDPlanner",
            path: "Sources/GTDPlanner"
        ),
        .testTarget(
            name: "GTDPlannerTests",
            dependencies: ["GTDPlanner"],
            path: "Tests/GTDPlannerTests"
        )
    ]
)

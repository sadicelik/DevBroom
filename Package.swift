// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevBroom",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DevBroomCore"),
        .executableTarget(name: "DevBroom", dependencies: ["DevBroomCore"]),
        .testTarget(name: "DevBroomCoreTests", dependencies: ["DevBroomCore"]),
    ]
)

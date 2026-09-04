// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WallShift",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WallShift",
            path: "Sources/WallShift"
        )
    ]
)

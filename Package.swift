// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SoundDistill",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SoundDistill", targets: ["SoundDistillApp"]),
        .executable(name: "sounddistill", targets: ["SoundDistillCLI"]),
        .library(name: "SoundDistillCore", targets: ["SoundDistillCore"])
    ],
    targets: [
        .target(name: "SoundDistillCore"),
        .executableTarget(
            name: "SoundDistillApp",
            dependencies: ["SoundDistillCore"]
        ),
        .executableTarget(
            name: "SoundDistillCLI",
            dependencies: ["SoundDistillCore"]
        ),
        .testTarget(
            name: "SoundDistillCoreTests",
            dependencies: ["SoundDistillCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)

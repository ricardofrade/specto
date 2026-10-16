// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Playback",
    platforms: [.iOS(.v26), .tvOS(.v26)],
    products: [
        .library(name: "Playback", targets: ["Playback"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(name: "Playback", dependencies: ["Core"]),
        .testTarget(name: "PlaybackTests", dependencies: ["Playback", "Core"])
    ]
)

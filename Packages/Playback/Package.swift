// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Playback",
    platforms: [.iOS(.v26), .tvOS(.v26)],
    products: [
        .library(name: "Playback", targets: ["Playback"]),
        .library(name: "PlaybackUI", targets: ["PlaybackUI"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../MPVRuntime")
    ],
    targets: [
        .target(name: "Playback", dependencies: ["Core", "MPVRuntime"]),
        // Views that host render surfaces; kept apart so `Playback` stays UI-free.
        .target(name: "PlaybackUI", dependencies: ["Playback"],
                swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "PlaybackTests", dependencies: ["Playback", "PlaybackUI", "Core"])
    ]
)

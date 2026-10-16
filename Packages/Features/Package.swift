// swift-tools-version: 6.2
import PackageDescription

/// Feature targets are UI code: main-actor by default (CLAUDE.md).
let featureSettings: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "Features",
    platforms: [.iOS(.v26), .tvOS(.v26)],
    products: [
        .library(name: "FeedFeature", targets: ["FeedFeature"]),
        .library(name: "InstancesFeature", targets: ["InstancesFeature"]),
        .library(name: "WatchFeature", targets: ["WatchFeature"]),
        .library(name: "SearchFeature", targets: ["SearchFeature"]),
        .library(name: "ChannelFeature", targets: ["ChannelFeature"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Library"),
        .package(path: "../Playback"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(name: "FeedFeature", dependencies: ["Core", "Library", "DesignSystem"],
                swiftSettings: featureSettings),
        .target(name: "InstancesFeature", dependencies: ["Core", "Library", "DesignSystem"],
                swiftSettings: featureSettings),
        .target(name: "WatchFeature",
                dependencies: ["Core", "Library", "DesignSystem", .product(name: "Playback", package: "Playback"),
                               .product(name: "PlaybackUI", package: "Playback")],
                swiftSettings: featureSettings),
        .target(name: "SearchFeature", dependencies: ["Core", "Library", "DesignSystem"],
                swiftSettings: featureSettings),
        .target(name: "ChannelFeature", dependencies: ["Core", "Library", "DesignSystem"],
                swiftSettings: featureSettings),
        .testTarget(name: "WatchFeatureTests", dependencies: ["WatchFeature"])
    ]
)

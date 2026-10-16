// swift-tools-version: 6.2
import PackageDescription

/// Feature targets are UI code: main-actor by default (CLAUDE.md).
let featureSettings: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "Features",
    platforms: [.iOS(.v26), .tvOS(.v26)],
    products: [
        .library(name: "FeedFeature", targets: ["FeedFeature"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Library"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(name: "FeedFeature", dependencies: ["Core", "Library", "DesignSystem"],
                swiftSettings: featureSettings)
    ]
)

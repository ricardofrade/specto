// swift-tools-version: 6.2
import PackageDescription

// Cast v2 sender for Chromecast / Google TV, written against the open protocol so the app
// ships no proprietary SDK or telemetry (docs/adr/0003-casting-without-the-sdk.md).
let package = Package(
    name: "Cast",
    platforms: [.iOS(.v26), .tvOS(.v26)],
    products: [
        .library(name: "Cast", targets: ["Cast"])
    ],
    targets: [
        .target(name: "Cast"),
        .testTarget(name: "CastTests", dependencies: ["Cast"])
    ]
)

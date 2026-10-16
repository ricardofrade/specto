// swift-tools-version: 6.2
import PackageDescription

// libmpv + FFmpeg, LGPL build only (MPVKit's non-GPL product; never `MPVKit-GPL`).
// MPVKit ships static archives; this package re-links them into ONE dynamic framework so
// the LGPL library stays replaceable in the shipped app (docs/spikes/mpv-build.md).
let package = Package(
    name: "MPVRuntime",
    platforms: [.iOS(.v26), .tvOS(.v26)],
    products: [
        .library(name: "MPVRuntime", type: .dynamic, targets: ["MPVRuntime"])
    ],
    dependencies: [
        .package(url: "https://github.com/mpvkit/MPVKit.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "MPVRuntime",
            dependencies: [.product(name: "MPVKit", package: "MPVKit")],
            // System frameworks libmpv's objects use that MPVKit doesn't declare.
            linkerSettings: [
                .linkedFramework("UIKit"),
                .linkedFramework("OpenGLES"),
                .linkedFramework("IOSurface"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("QuartzCore")
            ]
        )
    ]
)

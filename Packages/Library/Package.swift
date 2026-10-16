// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Library",
    platforms: [.iOS(.v26), .tvOS(.v26)],
    products: [
        .library(name: "Library", targets: ["Library"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(name: "Library", dependencies: ["Core", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "LibraryTests", dependencies: ["Library", .product(name: "GRDB", package: "GRDB.swift")])
    ]
)

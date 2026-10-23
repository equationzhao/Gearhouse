// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GearhouseCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "GearhouseCore", targets: ["GearhouseCore"])],
    targets: [
        .target(name: "GearhouseCore", resources: [.process("Resources")]),
        .testTarget(name: "GearhouseCoreTests", dependencies: ["GearhouseCore"])
    ]
)

// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FleksyCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "FleksyCore", targets: ["FleksyCore"]),
    ],
    targets: [
        .target(name: "FleksyCore"),
        .testTarget(name: "FleksyCoreTests", dependencies: ["FleksyCore"]),
    ]
)

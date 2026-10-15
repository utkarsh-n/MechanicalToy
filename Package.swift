// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MechanicalToy",
    platforms: [.iOS("27.0"), .macOS(.v14)],
    products: [.library(name: "MechanicalCore", targets: ["MechanicalCore"])],
    targets: [
        .target(name: "MechanicalCore"),
        .testTarget(name: "MechanicalCoreTests", dependencies: ["MechanicalCore"])
    ]
)

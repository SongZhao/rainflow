// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RainflowDomain",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "RainflowDomain", targets: ["RainflowDomain"])
    ],
    targets: [
        .target(name: "RainflowDomain"),
        .testTarget(name: "RainflowDomainTests", dependencies: ["RainflowDomain"])
    ]
)

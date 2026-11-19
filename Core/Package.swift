// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MiBancoCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [.library(name: "MiBancoCore", targets: ["MiBancoCore"])],
    targets: [
        .target(name: "MiBancoCore"),
        .testTarget(name: "MiBancoCoreTests", dependencies: ["MiBancoCore"]),
    ]
)

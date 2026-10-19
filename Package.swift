// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Prisme",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Prisme", targets: ["Prisme"]),
        .library(name: "PrismeCore", targets: ["PrismeCore"])
    ],
    targets: [
        .target(name: "PrismeCore"),
        .executableTarget(name: "Prisme", dependencies: ["PrismeCore"]),
        .testTarget(name: "PrismeCoreTests", dependencies: ["PrismeCore"])
    ]
)

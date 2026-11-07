// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CakraCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CakraCore", targets: ["CakraCore"]),
    ],
    targets: [
        .target(name: "CakraCore"),
        .testTarget(name: "CakraCoreTests", dependencies: ["CakraCore"]),
    ]
)

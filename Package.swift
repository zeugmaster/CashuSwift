// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "cashu-swift",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "cashu-swift",
            targets: ["cashu-swift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift.git", from: "0.14.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "cashu-swift",
            dependencies: [
                .product(name: "secp256k1", package: "secp256k1.swift")
            ]),

        .testTarget(
            name: "cashu-swiftTests",
            dependencies: ["cashu-swift"]),
    ]
)

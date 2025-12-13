// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CashuSwift",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "CashuSwift",
            targets: ["CashuSwift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1",
                 exact: "0.19.0"),
        .package(url: "https://github.com/zeugmaster/BIP32.git",
                 exact:"1.2.1"),
        .package(url: "https://github.com/mkrd/Swift-BigInt.git",
                 from: "2.0.0"),
        .package(url: "https://github.com/pengpengliu/BIP39.git",
                 from: "1.0.0"),
        .package(url: "https://github.com/myfreeweb/SwiftCBOR.git",
                 from: "0.4.4")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "CashuSwift",
            dependencies: [
                .product(name: "secp256k1", package: "swift-secp256k1"),
                .product(name: "BIP32", package: "BIP32"),
                .product(name: "BigNumber", package: "Swift-BigInt"),
                .product(name: "BIP39", package: "BIP39"),
                .product(name: "SwiftCBOR", package: "SwiftCBOR")
            ],
            swiftSettings: [
              .enableExperimentalFeature("StrictConcurrency")
            ]),
        .testTarget(
            name: "CashuSwiftTests",
            dependencies: ["CashuSwift"]),
    ]
)

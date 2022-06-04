// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "logseq-compiler",
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.0.1"),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON", from: "5.0.0"),
        .package(url: "https://github.com/twostraws/SwiftSlug", from: "0.3.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .executableTarget(
            name: "logseq-compiler",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "SwiftyJSON",
                "SwiftSlug"
            ]),
        .testTarget(
            name: "logseq-compilerTests",
            dependencies: ["logseq-compiler"]),
    ]
)

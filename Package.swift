// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package: Package = Package(
    name: "CustomLinter",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .executable(name: "CustomLinter", targets: ["CustomLinter"])
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-syntax.git", exact: "0.50800.0-SNAPSHOT-2022-12-29-a"),
        .package(url: "https://github.com/realm/SwiftLint.git", branch: "main"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .executableTarget(
            name: "CustomLinter",
            dependencies: [
                .product(name: "SwiftLintFramework", package: "SwiftLint"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "IDEUtils", package: "swift-syntax"),
            ]),
        .testTarget(
            name: "CustomLinterTests",
            dependencies: ["CustomLinter"]),
    ]
)

// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftMutationTesting",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "swift-mutation-testing", targets: ["swift-mutation-testing"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "603.0.0")
    ],
    targets: [
        .target(
            name: "SwiftMutationTesting",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            ],
            path: "Sources/SwiftMutationTesting",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "swift-mutation-testing",
            dependencies: ["SwiftMutationTesting"],
            path: "Sources/swift-mutation-testing",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "SwiftMutationTestingTests",
            dependencies: ["SwiftMutationTesting"],
            path: "Tests/SwiftMutationTestingTests",
            exclude: ["TestSupport/Fixtures"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)

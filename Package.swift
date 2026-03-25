// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftMutationTesting",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "swift-mutation-testing", targets: ["SwiftMutationTesting"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "602.0.0")
    ],
    targets: [
        .executableTarget(
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
        .testTarget(
            name: "SwiftMutationTestingTests",
            dependencies: ["SwiftMutationTesting"],
            path: "Tests/SwiftMutationTestingTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)

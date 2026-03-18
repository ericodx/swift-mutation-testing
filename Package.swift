// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftMutationTesting",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "swift-mutation-testing", targets: ["SwiftMutationTesting"])
    ],
    targets: [
        .executableTarget(
            name: "SwiftMutationTesting",
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
        .testTarget(
            name: "SwiftMutationTestingIntegrationTests",
            dependencies: ["SwiftMutationTesting"],
            path: "Tests/IntegrationTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)

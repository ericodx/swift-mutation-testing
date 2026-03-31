// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CalcLibrary",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CalcLibrary"),
        .testTarget(name: "CalcLibraryTests", dependencies: ["CalcLibrary"]),
    ]
)

import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("ConfigurationResolver xcodebuild arguments")
struct ConfigurationResolverXcodebuildArgumentsTests {
    private let resolver = ConfigurationResolver()

    @Test("Given --xcodebuild-arg twice, when resolved, then both arguments are kept in order")
    func theCommandLineFlags() throws {
        let root = try XcodeContainerLocatorTests.root(["App.xcodeproj"])
        defer { FileHelpers.cleanup(root) }

        let result = try resolver.resolve(
            cliArguments: Self.arguments(root, ["-allowProvisioningUpdates", "OTHER_SWIFT_FLAGS=-DMUTATING"]),
            fileValues: [:]
        )

        #expect(result.build.xcodebuildArguments == ["-allowProvisioningUpdates", "OTHER_SWIFT_FLAGS=-DMUTATING"])
    }

    @Test("Given the xcodebuild-args key in the file, when resolved, then its list is kept")
    func theFileKey() throws {
        let root = try XcodeContainerLocatorTests.root(["App.xcodeproj"])
        defer { FileHelpers.cleanup(root) }

        let result = try resolver.resolve(
            cliArguments: Self.arguments(root),
            fileValues: ["xcodebuild-args": "-allowProvisioningUpdates,-skipPackageUpdates"]
        )

        #expect(result.build.xcodebuildArguments == ["-allowProvisioningUpdates", "-skipPackageUpdates"])
    }

    @Test("Given arguments on the command line and in the file, when resolved, then the command line wins")
    func theCommandLineWins() throws {
        let root = try XcodeContainerLocatorTests.root(["App.xcodeproj"])
        defer { FileHelpers.cleanup(root) }

        let result = try resolver.resolve(
            cliArguments: Self.arguments(root, ["-allowProvisioningUpdates"]),
            fileValues: ["xcodebuild-args": "-skipPackageUpdates"]
        )

        #expect(result.build.xcodebuildArguments == ["-allowProvisioningUpdates"])
    }

    @Test("Given no xcodebuild argument, when resolved, then there is none")
    func noneByDefault() throws {
        let root = try XcodeContainerLocatorTests.root(["App.xcodeproj"])
        defer { FileHelpers.cleanup(root) }

        let result = try resolver.resolve(cliArguments: Self.arguments(root), fileValues: [:])

        #expect(result.build.xcodebuildArguments.isEmpty)
    }

    @Test(
        "Given an argument the tool sets itself, when resolved, then it is a usage error naming it",
        arguments: ["-scheme", "-destination", "-derivedDataPath", "-workspace", "-project", "test", "clean"]
    )
    func reservedArgumentsAreRefused(argument: String) throws {
        let root = try XcodeContainerLocatorTests.root(["App.xcodeproj"])
        defer { FileHelpers.cleanup(root) }

        #expect(
            throws: UsageError(
                message: "--xcodebuild-arg cannot pass \(argument): swift-mutation-testing sets it on every call itself"
            )
        ) {
            try resolver.resolve(cliArguments: Self.arguments(root, [argument]), fileValues: [:])
        }
    }

    @Test("Given xcodebuild arguments for a package, when resolved, then it is a usage error")
    func packagesAreRefused() throws {
        let root = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(root) }
        try "// swift-tools-version: 5.9".write(
            to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8
        )

        #expect(throws: UsageError(message: "--xcodebuild-arg applies to Xcode projects only")) {
            try resolver.resolve(
                cliArguments: ParsedArguments(
                    projectPath: root.path, build: .init(xcodebuildArguments: ["-allowProvisioningUpdates"])
                ),
                fileValues: [:]
            )
        }
    }

    @Test("Given the xcodebuild-args key, when the file is checked, then it is a known key")
    func theKeyIsKnown() {
        #expect(ConfigurationResolver.fileKeys.contains("xcodebuild-args"))
    }

    static func arguments(_ root: URL, _ xcodebuildArguments: [String] = []) -> ParsedArguments {
        ParsedArguments(
            projectPath: root.path,
            build: .init(scheme: "App", destination: "platform=macOS", xcodebuildArguments: xcodebuildArguments)
        )
    }
}

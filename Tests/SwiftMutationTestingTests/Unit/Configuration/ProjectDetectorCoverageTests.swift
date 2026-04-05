import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("ProjectDetector Coverage")
struct ProjectDetectorCoverageTests {
    private let projectJSON = """
        {
          "project": {
            "name": "MyApp",
            "schemes": ["MyApp", "MyAppTests"],
            "targets": ["MyApp", "MyAppTests", "MyAppUITests"]
          }
        }
        """

    @Test("Given SPM project with test targets, when detect called, then test targets are returned")
    func detectsSPMTestTargets() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try "// swift-tools-version: 6.0".write(
            to: dir.appendingPathComponent("Package.swift"),
            atomically: true, encoding: .utf8
        )

        let dumpJSON = """
            {
              "targets": [
                { "name": "MyLib", "type": "regular" },
                { "name": "MyLibTests", "type": "test" }
              ]
            }
            """
        let launcher = MockProcessLauncher(exitCode: 0, output: dumpJSON)
        let result = await ProjectDetector(launcher: launcher).detect(at: dir.path)

        #expect(result.testTarget == "MyLibTests")
    }

    @Test("Given SPM project and dump-package fails, when detect called, then empty test targets")
    func spmDumpFailureReturnsEmptyTestTargets() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try "// swift-tools-version: 6.0".write(
            to: dir.appendingPathComponent("Package.swift"),
            atomically: true, encoding: .utf8
        )

        let launcher = MockProcessLauncher(exitCode: 1, output: "")
        let result = await ProjectDetector(launcher: launcher).detect(at: dir.path)

        #expect(result.testTarget == nil)
    }

    @Test("Given Xcode project with test files containing import XCTest, when detect called, then xctest framework")
    func detectsXCTestFrameworkFromSourceFiles() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let xcodeprojURL = dir.appendingPathComponent("MyApp.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeprojURL, withIntermediateDirectories: true)

        let testDir = dir.appendingPathComponent("MyAppTests")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        try "import XCTest\nclass Tests: XCTestCase {}".write(
            to: testDir.appendingPathComponent("Tests.swift"),
            atomically: true, encoding: .utf8
        )

        let detector = ProjectDetector(launcher: MockProcessLauncher(exitCode: 0, output: projectJSON))
        let result = await detector.detect(at: dir.path)

        #expect(result.testingFramework == .xctest)
    }

    @Test("Given Xcode project with both import XCTest and import Testing, when detect called, then swiftTesting")
    func detectsBothFrameworksReturnsSwiftTesting() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let xcodeprojURL = dir.appendingPathComponent("MyApp.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeprojURL, withIntermediateDirectories: true)

        let testDir = dir.appendingPathComponent("MyAppTests")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        try "import XCTest\nclass OldTests: XCTestCase {}".write(
            to: testDir.appendingPathComponent("OldTests.swift"),
            atomically: true, encoding: .utf8
        )
        try "import Testing\n@Suite struct NewTests {}".write(
            to: testDir.appendingPathComponent("NewTests.swift"),
            atomically: true, encoding: .utf8
        )

        let detector = ProjectDetector(launcher: MockProcessLauncher(exitCode: 0, output: projectJSON))
        let result = await detector.detect(at: dir.path)

        #expect(result.testingFramework == .swiftTesting)
    }

    @Test("Given Xcode project with no test files, when detect called, then swiftTesting default")
    func noTestFilesDefaultsToSwiftTesting() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let xcodeprojURL = dir.appendingPathComponent("MyApp.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeprojURL, withIntermediateDirectories: true)

        let detector = ProjectDetector(launcher: MockProcessLauncher(exitCode: 0, output: projectJSON))
        let result = await detector.detect(at: dir.path)

        #expect(result.testingFramework == .swiftTesting)
    }

    @Test("Given tvOS project with Apple TV but no 4K, when detect called, then uses Apple TV")
    func tvOSFallsBackToAppleTVWhenNo4K() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let xcodeprojURL = dir.appendingPathComponent("MyApp.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeprojURL, withIntermediateDirectories: true)
        try "SDKROOT = appletvos;".write(
            to: xcodeprojURL.appendingPathComponent("project.pbxproj"),
            atomically: true, encoding: .utf8
        )

        let simctlJSON = """
            {
              "devices": {
                "com.apple.CoreSimulator.SimRuntime.tvOS-17-0": [
                  { "name": "Apple TV", "isAvailable": true }
                ]
              }
            }
            """
        let launcher = MockProcessLauncher(
            exitCode: 0,
            output: projectJSON,
            responses: ["xcrun": (exitCode: 0, output: simctlJSON)]
        )
        let result = await ProjectDetector(launcher: launcher).detect(at: dir.path)

        #expect(result.destination.contains("Apple TV"))
        #expect(result.destination.contains("tvOS Simulator"))
    }

    @Test("Given workspace JSON without schemes key, when detect called, then schemes default to empty")
    func missingSchemeKeyDefaultsToEmpty() async throws {
        let json = #"{"workspace":{"name":"App"}}"#
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("App.xcworkspace"),
            withIntermediateDirectories: true
        )

        let result = await ProjectDetector(launcher: MockProcessLauncher(exitCode: 0, output: json))
            .detect(at: dir.path)

        #expect(result.scheme == nil)
        #expect(result.allSchemes.isEmpty)
    }
}

import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("ProjectDetector")
struct ProjectDetectorTests {
    private let projectJSON = """
        {
          "project": {
            "name": "MyApp",
            "schemes": ["MyApp", "MyAppTests"],
            "targets": ["MyApp", "MyAppTests", "MyAppUITests"]
          }
        }
        """

    private let workspaceJSON = """
        {
          "workspace": {
            "name": "MyApp",
            "schemes": ["MyApp", "MyAppTests"]
          }
        }
        """

    @Test("Given project JSON with targets, when detect called, then scheme and testTarget are set")
    func detectsSchemeAndTestTargetFromProjectJSON() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("MyApp.xcodeproj"),
            withIntermediateDirectories: true
        )

        let detector = ProjectDetector(launcher: MockProcessLauncher(exitCode: 0, output: projectJSON))
        let result = await detector.detect(at: dir.path)

        #expect(result.scheme == "MyApp")
        #expect(result.allSchemes == ["MyApp", "MyAppTests"])
        #expect(result.testTarget == "MyAppTests")
    }

    @Test("Given project JSON with UITests but no unit tests, when detect called, then UITests target is returned")
    func fallsBackToUITestsWhenNoUnitTests() async throws {
        let json = """
            { "project": { "name": "App", "schemes": ["App"], "targets": ["App", "AppUITests"] } }
            """
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("App.xcodeproj"),
            withIntermediateDirectories: true
        )

        let detector = ProjectDetector(launcher: MockProcessLauncher(exitCode: 0, output: json))
        let result = await detector.detect(at: dir.path)

        #expect(result.testTarget == "AppUITests")
    }

    @Test("Given workspace JSON without targets, when detect called, then scheme name is used as testTarget hint")
    func detectsTestTargetFromSchemeNamesForWorkspace() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("MyApp.xcworkspace"),
            withIntermediateDirectories: true
        )

        let detector = ProjectDetector(launcher: MockProcessLauncher(exitCode: 0, output: workspaceJSON))
        let result = await detector.detect(at: dir.path)

        #expect(result.scheme == "MyApp")
        #expect(result.testTarget == "MyAppTests")
    }

    @Test("Given xcodeproj with iphoneos SDKROOT, when detect called, then destination is iOS Simulator")
    func detectsiOSDestinationFromPbxproj() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let xcodeprojURL = dir.appendingPathComponent("MyApp.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeprojURL, withIntermediateDirectories: true)
        try "SDKROOT = iphoneos;".write(
            to: xcodeprojURL.appendingPathComponent("project.pbxproj"),
            atomically: true, encoding: .utf8
        )

        let detector = ProjectDetector(launcher: MockProcessLauncher(exitCode: 0, output: projectJSON))
        let result = await detector.detect(at: dir.path)

        #expect(result.destination.contains("iOS Simulator"))
    }

    @Test("Given xcodeproj with macosx SDKROOT, when detect called, then destination is macOS")
    func detectsmacOSDestinationFromPbxproj() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let xcodeprojURL = dir.appendingPathComponent("MyApp.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeprojURL, withIntermediateDirectories: true)
        try "SDKROOT = macosx;".write(
            to: xcodeprojURL.appendingPathComponent("project.pbxproj"),
            atomically: true, encoding: .utf8
        )

        let detector = ProjectDetector(launcher: MockProcessLauncher(exitCode: 0, output: projectJSON))
        let result = await detector.detect(at: dir.path)

        #expect(result.destination == "platform=macOS")
    }

    @Test("Given xcodebuild exits with non-zero code, when detect called, then empty project is returned")
    func returnsEmptyWhenXcodebuildFails() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("MyApp.xcodeproj"),
            withIntermediateDirectories: true
        )

        let detector = ProjectDetector(launcher: MockProcessLauncher(exitCode: 1, output: ""))
        let result = await detector.detect(at: dir.path)

        #expect(result.scheme == nil)
        #expect(result.allSchemes.isEmpty)
    }

    @Test("Given directory with no Xcode container, when detect called, then empty project is returned")
    func returnsEmptyWhenNoContainerFound() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let detector = ProjectDetector(launcher: MockProcessLauncher(exitCode: 0, output: projectJSON))
        let result = await detector.detect(at: dir.path)

        #expect(result.scheme == nil)
        #expect(result.allSchemes.isEmpty)
    }

    @Test("Given malformed JSON, when detect called, then empty project is returned")
    func returnsEmptyForMalformedJSON() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("MyApp.xcodeproj"),
            withIntermediateDirectories: true
        )

        let detector = ProjectDetector(launcher: MockProcessLauncher(exitCode: 0, output: "not json"))
        let result = await detector.detect(at: dir.path)

        #expect(result.scheme == nil)
        #expect(result.allSchemes.isEmpty)
    }
}

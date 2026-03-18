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
            "targets": ["MyApp", "MyAppTests"]
          }
        }
        """

    private let workspaceJSON = """
        {
          "workspace": {
            "name": "MyApp",
            "schemes": ["MyApp"]
          }
        }
        """

    @Test("Given xcodebuild returns project JSON, when detect called, then first scheme is returned")
    func detectsFirstSchemeFromProjectJSON() async throws {
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
    }

    @Test("Given xcodebuild returns workspace JSON, when detect called, then scheme is returned")
    func detectsSchemeFromWorkspaceJSON() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("MyApp.xcworkspace"),
            withIntermediateDirectories: true
        )

        let detector = ProjectDetector(launcher: MockProcessLauncher(exitCode: 0, output: workspaceJSON))
        let result = await detector.detect(at: dir.path)

        #expect(result.scheme == "MyApp")
        #expect(result.allSchemes == ["MyApp"])
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

    @Test("Given xcodebuild returns malformed JSON, when detect called, then empty project is returned")
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

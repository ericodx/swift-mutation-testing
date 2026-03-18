import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("ConfigurationFileWriter")
struct ConfigurationFileWriterTests {
    private let writer = ConfigurationFileWriter()

    @Test("Given no detected scheme, when write called, then scheme line is commented")
    func schemeLineIsCommentedWhenNotDetected() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(to: dir.path, project: .empty)

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("# scheme: MyApp"))
        #expect(!content.contains("\nscheme:"))
    }

    @Test("Given detected scheme, when write called, then scheme line is filled and uncommented")
    func schemeLineIsFilledWhenDetected() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(to: dir.path, project: DetectedProject(scheme: "MyApp", allSchemes: ["MyApp"]))

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("scheme: MyApp"))
        #expect(!content.contains("# scheme:"))
    }

    @Test("Given multiple schemes detected, when write called, then available schemes comment is included")
    func availableSchemesCommentIsIncludedForMultipleSchemes() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(
            to: dir.path,
            project: DetectedProject(scheme: "MyApp", allSchemes: ["MyApp", "MyAppTests"])
        )

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("# Available schemes: MyApp, MyAppTests"))
    }

    @Test("Given generated config file, when parsed by ConfigurationFileParser, then destination key is present")
    func generatedFileContainsDestination() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(to: dir.path, project: DetectedProject(scheme: "App", allSchemes: ["App"]))

        let values = try ConfigurationFileParser().parse(at: dir.path)
        #expect(values["scheme"] == "App")
        #expect(values["destination"] == "platform=macOS")
    }

    @Test("Given existing config file, when write called, then throws UsageError")
    func throwsWhenFileAlreadyExists() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(to: dir.path, project: .empty)

        #expect(throws: UsageError.self) {
            try writer.write(to: dir.path, project: .empty)
        }
    }
}

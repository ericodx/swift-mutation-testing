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

        try writer.write(
            to: dir.path,
            project: DetectedProject(
                scheme: "MyApp", allSchemes: ["MyApp"], testTarget: nil, destination: "platform=macOS"
            )
        )

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("scheme: MyApp"))
        #expect(!content.contains("# scheme:"))
    }

    @Test("Given detected testTarget, when write called, then testTarget line is filled and uncommented")
    func testTargetLineIsFilledWhenDetected() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(
            to: dir.path,
            project: DetectedProject(
                scheme: "MyApp", allSchemes: ["MyApp"], testTarget: "MyAppTests", destination: "platform=macOS"
            )
        )

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("testTarget: MyAppTests"))
        #expect(!content.contains("# testTarget:"))
    }

    @Test("Given detected destination, when write called, then destination is filled")
    func destinationIsAlwaysFilled() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(
            to: dir.path,
            project: DetectedProject(
                scheme: "MyApp", allSchemes: ["MyApp"], testTarget: nil,
                destination: "platform=iOS Simulator,OS=latest,name=iPhone 16 Pro"
            )
        )

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("destination: platform=iOS Simulator"))
    }

    @Test("Given any project, when write called, then timeout and concurrency are always filled")
    func timeoutAndConcurrencyAreAlwaysFilled() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(to: dir.path, project: .empty)

        let values = try ConfigurationFileParser().parse(at: dir.path)
        #expect(values["timeout"] == "60")
        #expect(values["concurrency"] == "4")
    }

    @Test("Given multiple schemes detected, when write called, then available schemes comment is included")
    func availableSchemesCommentIsIncludedForMultipleSchemes() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(
            to: dir.path,
            project: DetectedProject(
                scheme: "MyApp", allSchemes: ["MyApp", "MyAppTests"], testTarget: nil, destination: "platform=macOS"
            )
        )

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("# Available schemes: MyApp, MyAppTests"))
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

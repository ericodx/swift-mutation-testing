import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("ConfigurationFileWriter")
struct ConfigurationFileWriterTests {
    private let writer = ConfigurationFileWriter()

    @Test("Given any project, when write called, then header comment is present")
    func headerCommentIsPresent() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(to: dir.path, project: .empty)

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("# swift-mutation-testing configuration"))
    }

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
                kind: .xcode(scheme: "MyApp", allSchemes: ["MyApp"], destination: "platform=macOS"),
                testTarget: nil
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
                kind: .xcode(scheme: "MyApp", allSchemes: ["MyApp"], destination: "platform=macOS"),
                testTarget: "MyAppTests"
            )
        )

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("test-target: MyAppTests"))
        #expect(!content.contains("# test-target:"))
    }

    @Test("Given detected destination, when write called, then destination is filled")
    func destinationIsAlwaysFilled() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(
            to: dir.path,
            project: DetectedProject(
                kind: .xcode(
                    scheme: "MyApp", allSchemes: ["MyApp"],
                    destination: "platform=iOS Simulator,OS=latest,name=iPhone 16 Pro"
                ),
                testTarget: nil
            )
        )

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("destination: platform=iOS Simulator"))
    }

    @Test("Given any project, when write called, then timeout is always filled")
    func timeoutIsAlwaysFilled() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(to: dir.path, project: .empty)

        let values = try ConfigurationFileParser().parse(at: dir.path)
        #expect(values["timeout"] == "120")
        #expect(values["concurrency"] == "4")
    }

    @Test("Given multiple schemes detected, when write called, then available schemes comment is included")
    func availableSchemesCommentIsIncludedForMultipleSchemes() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(
            to: dir.path,
            project: DetectedProject(
                kind: .xcode(scheme: "MyApp", allSchemes: ["MyApp", "MyAppTests"], destination: "platform=macOS"),
                testTarget: nil
            )
        )

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("# Available schemes: MyApp, MyAppTests"))
    }

    @Test("Given detected testTarget, when write called, then exclude uses YAML list with test target")
    func excludeUsesTestTargetAsDefault() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(
            to: dir.path,
            project: DetectedProject(
                kind: .xcode(scheme: "MyApp", allSchemes: ["MyApp"], destination: "platform=macOS"),
                testTarget: "MyAppTests"
            )
        )

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("exclude:"))
        #expect(content.contains("  - \"/MyAppTests/\""))
        #expect(!content.contains("# exclude:"))
    }

    @Test("Given no testTarget, when write called, then exclude section is commented")
    func excludeIsCommentedWhenNoTestTarget() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(to: dir.path, project: .empty)

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("# exclude:"))
        #expect(!content.contains("\nexclude:"))
    }

    @Test("Given any project, when write called, then noCache option is commented")
    func noCacheOptionIsCommented() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(to: dir.path, project: .empty)

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("# no-cache: true"))
        #expect(!content.contains("\nno-cache:"))
    }

    @Test("Given any project, when write called, then output is set to mutation-report.json")
    func outputIsAlwaysFilled() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(to: dir.path, project: .empty)

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("output: mutation-report.json"))
        #expect(!content.contains("# output:"))
    }

    @Test("Given any project, when write called, then mutators section lists all operators as active")
    func mutatorsSectionListsAllOperators() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(to: dir.path, project: .empty)

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("mutators:"))
        for name in DiscoveryPipeline.allOperatorNames {
            #expect(content.contains("  - name: \(name)"))
            #expect(content.contains("    active: true"))
        }
    }

    @Test("Given Xcode project, when write called, then testingFramework option is included")
    func testingFrameworkOptionIncludedForXcode() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(
            to: dir.path,
            project: DetectedProject(
                kind: .xcode(scheme: "MyApp", allSchemes: ["MyApp"], destination: "platform=macOS"),
                testTarget: nil
            )
        )

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("testing-framework"))
        #expect(content.contains("swift-testing"))
    }

    @Test("Given Xcode project with xctest, when write called, then concurrency is 1")
    func xcTestConcurrencyIsOneInTemplate() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(
            to: dir.path,
            project: DetectedProject(
                kind: .xcode(scheme: "MyApp", allSchemes: ["MyApp"], destination: "platform=macOS"),
                testTarget: nil,
                testingFramework: .xctest
            )
        )

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("testing-framework: xctest"))
        #expect(content.contains("concurrency: 1"))
    }

    @Test("Given SPM project, when write called, then testingFramework option is not included")
    func testingFrameworkOptionNotIncludedForSPM() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(
            to: dir.path,
            project: DetectedProject(
                kind: .spm(testTargets: ["MyTests"]),
                testTarget: nil
            )
        )

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(!content.contains("testing-framework"))
    }

    @Test(
        "Given SPM with multiple test targets and testTarget, when write called, then config is correct"
    )
    func spmMultipleTestTargetsAndTestTarget() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(
            to: dir.path,
            project: DetectedProject(
                kind: .spm(testTargets: ["FooTests", "BarTests"]),
                testTarget: "FooTests"
            )
        )

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("# Available test targets: FooTests, BarTests"))
        #expect(content.contains("test-target: FooTests"))
        #expect(!content.contains("# test-target:"))
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

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

    @Test("Given any project, when write called, then build-timeout is offered as a commented line")
    func buildTimeoutLineIsOffered() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(to: dir.path, project: .empty)

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("# build-timeout: 240"))
    }

    @Test("Given an SPM project, when write called, then build-timeout is offered as a commented line")
    func buildTimeoutLineIsOfferedForSPM() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let project = DetectedProject(kind: .spm(testTargets: ["AppTests"]), testTarget: "AppTests")
        try writer.write(to: dir.path, project: project)

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("# build-timeout: 240"))
    }

    @Test(
        "Given either project type, when write called, then the quality gate keys are offered as commented lines",
        arguments: [
            DetectedProject.empty,
            DetectedProject(kind: .spm(testTargets: ["AppTests"]), testTarget: "AppTests"),
        ]
    )
    func gateKeysAreOffered(project: DetectedProject) throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(to: dir.path, project: project)

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("# Quality gate — a failed gate exits with code 2"))
        #expect(content.contains("# min-score: 80"))
        #expect(content.contains("# baseline: .swift-mutation-testing-baseline.json"))
        #expect(content.contains("# max-score-drop: 2"))
        #expect(content.contains("# max-new-survivors: 0"))
        #expect(content.contains("# max-integrity-warnings: 0"))
    }

    @Test("Given any project, when write called, then the SARIF and Markdown outputs are offered as comments")
    func sarifAndMarkdownOutputsAreOffered() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(to: dir.path, project: .empty)

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("# sarif-output: mutation-report.sarif"))
        #expect(content.contains("# markdown-output: mutation-summary.md"))
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

    @Test("Given any project, when write called, then the operator tier is offered as a commented line with its docs")
    func operatorTierIsOfferedAsAComment() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(to: dir.path, project: .empty)

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("# operator-tier: default"))
        #expect(content.contains("Docs/OPERATORS.md"))
    }

    @Test("Given any project, when write called, then mutators section lists all operators as active")
    func mutatorsSectionListsAllOperators() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(to: dir.path, project: .empty)

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("mutators:"))
        for name in OperatorRegistry.allOperatorNames {
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

    @Test("Given a detected workspace, when written, then the file names it so the run needs no flag")
    func theContainerIsWritten() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        var project = DetectedProject(
            kind: .xcode(scheme: "App", allSchemes: ["App"], destination: "platform=macOS"), testTarget: nil
        )
        project.xcodeContainer = .workspace("App.xcworkspace")

        try writer.write(to: dir.path, project: project)

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("\nworkspace: App.xcworkspace\n"))
        let values = try ConfigurationFileParser().parse(at: dir.path)
        #expect(values["workspace"] == "App.xcworkspace")
        #expect(values["project"] == nil)
    }

    @Test("Given several containers and none chosen, when written, then the reason and every candidate are commented")
    func ambiguityIsWrittenAsComments() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        var project = DetectedProject(
            kind: .xcode(scheme: nil, allSchemes: [], destination: "platform=macOS"), testTarget: nil
        )
        project.containerNote = "found A.xcworkspace and B.xcworkspace at the project root"
        project.containerCandidates = [
            .workspace("A.xcworkspace"), .workspace("B.xcworkspace"), .project("A.xcodeproj"),
        ]

        try writer.write(to: dir.path, project: project)

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("# No workspace or project was chosen: found A.xcworkspace and B.xcworkspace"))
        #expect(content.contains("# workspace: A.xcworkspace\n# workspace: B.xcworkspace\n# project: A.xcodeproj"))
        let values = try ConfigurationFileParser().parse(at: dir.path)
        #expect(values["workspace"] == nil)
    }

    @Test("Given an Xcode project, when write called, then xcodebuild-args is offered as a commented list")
    func xcodebuildArgumentsAreOffered() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(to: dir.path, project: .empty)

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(content.contains("# xcodebuild-args:\n#   - -allowProvisioningUpdates"))
    }

    @Test("Given an SPM project, when write called, then xcodebuild-args is not offered")
    func xcodebuildArgumentsAreNotOfferedForSPM() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        try writer.write(to: dir.path, project: DetectedProject(kind: .spm(testTargets: ["AppTests"]), testTarget: nil))

        let content = try String(contentsOf: dir.appendingPathComponent(".swift-mutation-testing.yml"), encoding: .utf8)
        #expect(!content.contains("xcodebuild-args"))
    }
}

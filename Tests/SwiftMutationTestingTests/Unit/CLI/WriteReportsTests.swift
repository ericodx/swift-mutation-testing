import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("SwiftMutationTesting.writeReports", .serialized)
struct WriteReportsTests {
    @Test("Given no output paths configured, when writeReports called, then no files are created")
    func noOutputPathsProducesNoFiles() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let configuration = makeConfiguration(projectPath: dir.path)

        SwiftMutationTesting.writeReports(makeEmptySummary(), configuration: configuration)

        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.isEmpty)
    }

    @Test("Given json output path, when writeReports called, then json file is written")
    func jsonOutputPathWritesFile() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("report.json").path
        let configuration = makeConfiguration(projectPath: dir.path, output: outputPath)

        SwiftMutationTesting.writeReports(makeEmptySummary(), configuration: configuration)

        #expect(FileManager.default.fileExists(atPath: outputPath))
    }

    @Test("Given html output path, when writeReports called, then html file is written")
    func htmlOutputPathWritesFile() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("report.html").path
        let configuration = makeConfiguration(projectPath: dir.path, htmlOutput: outputPath)

        SwiftMutationTesting.writeReports(makeEmptySummary(), configuration: configuration)

        #expect(FileManager.default.fileExists(atPath: outputPath))
    }

    @Test("Given sonar output path, when writeReports called, then sonar file is written")
    func sonarOutputPathWritesFile() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let outputPath = dir.appendingPathComponent("sonar.json").path
        let configuration = makeConfiguration(projectPath: dir.path, sonarOutput: outputPath)

        SwiftMutationTesting.writeReports(makeEmptySummary(), configuration: configuration)

        #expect(FileManager.default.fileExists(atPath: outputPath))
    }

    @Test("Given invalid json output path, when writeReports called, then does not crash")
    func invalidJsonOutputPathDoesNotCrash() {
        let configuration = makeConfiguration(
            projectPath: "/tmp",
            output: "/nonexistent/dir/report.json"
        )
        SwiftMutationTesting.writeReports(makeEmptySummary(), configuration: configuration)
    }

    @Test("Given invalid html output path, when writeReports called, then does not crash")
    func invalidHtmlOutputPathDoesNotCrash() {
        let configuration = makeConfiguration(
            projectPath: "/tmp",
            htmlOutput: "/nonexistent/dir/report.html"
        )
        SwiftMutationTesting.writeReports(makeEmptySummary(), configuration: configuration)
    }

    @Test("Given invalid sonar output path, when writeReports called, then does not crash")
    func invalidSonarOutputPathDoesNotCrash() {
        let configuration = makeConfiguration(
            projectPath: "/tmp",
            sonarOutput: "/nonexistent/dir/sonar.json"
        )
        SwiftMutationTesting.writeReports(makeEmptySummary(), configuration: configuration)
    }

    @Test("Given all three output paths, when writeReports called, then all three files are written")
    func allThreeOutputPathsWriteFiles() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let jsonPath = dir.appendingPathComponent("report.json").path
        let htmlPath = dir.appendingPathComponent("report.html").path
        let sonarPath = dir.appendingPathComponent("sonar.json").path
        let configuration = makeConfiguration(
            projectPath: dir.path,
            output: jsonPath,
            htmlOutput: htmlPath,
            sonarOutput: sonarPath
        )

        SwiftMutationTesting.writeReports(makeEmptySummary(), configuration: configuration)

        #expect(FileManager.default.fileExists(atPath: jsonPath))
        #expect(FileManager.default.fileExists(atPath: htmlPath))
        #expect(FileManager.default.fileExists(atPath: sonarPath))
    }
}

private func makeConfiguration(
    projectPath: String,
    output: String? = nil,
    htmlOutput: String? = nil,
    sonarOutput: String? = nil
) -> RunnerConfiguration {
    RunnerConfiguration(
        projectPath: projectPath,
        build: .init(
            projectType: .xcode(scheme: "MyScheme", destination: "platform=macOS"),
            timeout: 60, concurrency: 1, noCache: false),
        reporting: .init(output: output, htmlOutput: htmlOutput, sonarOutput: sonarOutput, quiet: true),
        filter: .init(excludePatterns: [], operators: [])
    )
}

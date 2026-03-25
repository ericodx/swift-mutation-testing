import Foundation
import Testing

@testable import SwiftMutationTesting

private struct IOSSimulatorMock: ProcessLaunching {
    let listJSON: String
    let cloneUDID: String

    func launch(
        executableURL: URL, arguments: [String], workingDirectoryURL: URL, timeout: Double
    ) async throws -> Int32 {
        1
    }

    func launchCapturing(
        executableURL: URL, arguments: [String], environment: [String: String]?,
        workingDirectoryURL: URL, timeout: Double
    ) async throws -> (exitCode: Int32, output: String) {
        if arguments.contains("clone") { return (0, cloneUDID + "\n") }
        return (0, listJSON)
    }
}

@Suite("SwiftMutationTesting.run")
struct SwiftMutationTestingRunTests {
    @Test("Given --help flag, when run called, then returns success")
    func helpFlagReturnsSuccess() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let result = await SwiftMutationTesting.run(args: ["--help"])

        #expect(result == .success)
    }

    @Test("Given --help flag, when run called, then prints usage to stdout")
    func helpFlagPrintsUsage() async {
        let output = await captureOutput {
            _ = await SwiftMutationTesting.run(args: ["--help"])
        }

        #expect(output.contains("swift-mutation-testing"))
    }

    @Test("Given --version flag, when run called, then returns success")
    func versionFlagReturnsSuccess() async {
        let result = await SwiftMutationTesting.run(args: ["--version"])

        #expect(result == .success)
    }

    @Test("Given --version flag, when run called, then prints version to stdout")
    func versionFlagPrintsVersion() async {
        let output = await captureOutput {
            _ = await SwiftMutationTesting.run(args: ["--version"])
        }

        #expect(output.contains("0.1.0"))
    }

    @Test("Given no scheme, when run called, then returns error")
    func missingSchemeReturnsError() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let result = await SwiftMutationTesting.run(args: [dir.path])

        #expect(result == .error)
    }

    @Test("Given scheme but no destination, when run called, then returns error")
    func missingDestinationReturnsError() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let result = await SwiftMutationTesting.run(args: [dir.path, "--scheme", "App"])

        #expect(result == .error)
    }

    @Test("Given unknown flag, when run called, then returns error")
    func unknownFlagReturnsError() async {
        let result = await SwiftMutationTesting.run(args: ["--unknown-flag-xyz"])

        #expect(result == .error)
    }

    @Test("Given init command on empty directory, when run called, then returns success and creates yml")
    func initCommandCreatesConfigFile() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let result = await SwiftMutationTesting.run(args: ["init", dir.path])

        #expect(result == .success)
        let ymlPath = dir.appendingPathComponent(".swift-mutation-testing.yml").path
        #expect(FileManager.default.fileExists(atPath: ymlPath))
    }

    @Test("Given init command when yml already exists, when run called, then returns error")
    func initCommandFailsWhenYmlExists() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let ymlURL = dir.appendingPathComponent(".swift-mutation-testing.yml")
        try "existing".write(to: ymlURL, atomically: true, encoding: .utf8)

        let result = await SwiftMutationTesting.run(args: ["init", dir.path])

        #expect(result == .error)
    }
}

@Suite("SwiftMutationTesting.writeReports", .serialized)
struct WriteReportsTests {
    @Test("Given no output paths configured, when writeReports called, then no files are created")
    func noOutputPathsProducesNoFiles() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let configuration = makeConfiguration(projectPath: dir.path)
        let summary = makeEmptySummary()

        SwiftMutationTesting.writeReports(summary, configuration: configuration)

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

    private func makeEmptySummary() -> RunnerSummary {
        RunnerSummary(results: [], totalDuration: 0)
    }

    private func makeConfiguration(
        projectPath: String,
        output: String? = nil,
        htmlOutput: String? = nil,
        sonarOutput: String? = nil
    ) -> RunnerConfiguration {
        RunnerConfiguration(
            projectPath: projectPath,
            scheme: "MyScheme",
            destination: "platform=macOS",
            testTarget: nil,
            timeout: 60,
            concurrency: 1,
            noCache: false,
            output: output,
            htmlOutput: htmlOutput,
            sonarOutput: sonarOutput,
            quiet: true
        )
    }
}

@Suite("SwiftMutationTesting.run execution path")
struct SwiftMutationTestingExecutionPathTests {
    @Test("Given valid config with macOS destination and no Swift files, when run called, then returns success")
    func mainExecutionPathWithEmptyProjectReturnsSuccess() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let yml = "scheme: NonExistentScheme\ndestination: platform=macOS\n"
        try yml.write(to: dir.appendingPathComponent(".swift-mutation-testing.yml"), atomically: true, encoding: .utf8)

        let result = await SwiftMutationTesting.run(
            args: [dir.path],
            launcher: MockProcessLauncher(exitCode: 1)
        )

        #expect(result == .success)
    }

    @Test("Given valid config with quiet false and no Swift files, when run called, then returns success")
    func quietFalseExecutionPathReturnsSuccess() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let yml = "scheme: NonExistentScheme\ndestination: platform=macOS\nquiet: false\n"
        try yml.write(to: dir.appendingPathComponent(".swift-mutation-testing.yml"), atomically: true, encoding: .utf8)

        let result = await SwiftMutationTesting.run(
            args: [dir.path],
            launcher: MockProcessLauncher(exitCode: 1)
        )

        #expect(result == .success)
    }

    @Test("Given iOS Simulator destination with invalid simctl output, when run called, then returns error")
    func iOSSimulatorDestinationWithInvalidSimctlOutputReturnsError() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let yml = "scheme: NonExistentScheme\ndestination: \"platform=iOS Simulator,name=iPhone 15\"\n"
        try yml.write(to: dir.appendingPathComponent(".swift-mutation-testing.yml"), atomically: true, encoding: .utf8)

        let result = await SwiftMutationTesting.run(
            args: [dir.path],
            launcher: MockProcessLauncher(exitCode: 1, output: "not-valid-json")
        )

        #expect(result == .error)
    }

    @Test("Given iOS Simulator destination with valid simctl output, when run called, then SimulatorPool is created")
    func iOSSimulatorPoolIsCreatedWhenDestinationRequiresSimulator() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let cloneUDID = "CLONE-UDID"
        let listJSON = """
            {"devices":{"com.apple.runtime.iOS":[
                {"udid":"BASE-UDID","name":"iPhone 15","state":"Booted"},
                {"udid":"\(cloneUDID)","name":"Clone","state":"Booted"}
            ]}}
            """
        let yml = "scheme: NonExistentScheme\ndestination: \"platform=iOS Simulator,name=iPhone 15\"\n"
        try yml.write(to: dir.appendingPathComponent(".swift-mutation-testing.yml"), atomically: true, encoding: .utf8)

        let result = await SwiftMutationTesting.run(
            args: [dir.path],
            launcher: IOSSimulatorMock(listJSON: listJSON, cloneUDID: cloneUDID)
        )

        #expect(result == .success)
    }

    @Test("Given corrupted cache file at project path, when run called, then returns error")
    func corruptedCacheFileReturnsError() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let yml = "scheme: NonExistentScheme\ndestination: platform=macOS\n"
        try yml.write(to: dir.appendingPathComponent(".swift-mutation-testing.yml"), atomically: true, encoding: .utf8)

        let cacheDir = dir.appendingPathComponent(CacheStore.directoryName)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try "not valid json at all!!!".write(
            to: cacheDir.appendingPathComponent("results.json"),
            atomically: true,
            encoding: .utf8
        )

        let result = await SwiftMutationTesting.run(
            args: [dir.path],
            launcher: MockProcessLauncher(exitCode: 1)
        )

        #expect(result == .error)
    }
}

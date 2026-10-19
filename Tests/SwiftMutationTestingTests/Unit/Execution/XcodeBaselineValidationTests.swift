import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("Baseline validation — Xcode")
struct XcodeBaselineValidationTests {

    @Test("Given the unmutated Xcode suite reports failing tests, when execute called, then the run ends naming them")
    func failingBaselineEndsRunNamingTests() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = XcodeBaselineOutcomeMock(
            exitCode: 65,
            output: """
                Test Case '-[AppTests testBar]' failed (0.001 seconds).
                Test Case '-[AppTests testBaz]' failed (0.002 seconds).
                """
        )
        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            launcher: launcher
        )

        let error = await #expect(throws: BaselineError.self) {
            _ = try await executor.execute(try makeXcodeInput(in: dir))
        }

        #expect(error == .testsFailed(tests: ["AppTests.testBar", "AppTests.testBaz"]))
        #expect(await launcher.mutantTestRuns == 0)
    }

    @Test("Given the unmutated Xcode suite fails with keep-logs, when execute called, then its output is baseline.log")
    func failingBaselineOutputIsKept() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let logs = dir.appendingPathComponent("logs")
        let output = "Test Case '-[AppTests testBar]' failed (0.001 seconds).\nerror: the reason"
        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, keepLogsPath: logs.path),
            launcher: XcodeBaselineOutcomeMock(exitCode: 65, output: output)
        )

        await #expect(throws: BaselineError.self) {
            _ = try await executor.execute(try makeXcodeInput(in: dir))
        }

        let kept = try String(contentsOf: logs.appendingPathComponent("baseline.log"), encoding: .utf8)
        #expect(kept == output)
    }

    @Test("Given the unmutated Xcode suite does not finish, when execute called, then the run ends with didNotFinish")
    func timedOutBaselineEndsRun() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = XcodeBaselineOutcomeMock(exitCode: -1, output: "Test Suite 'All tests' started")
        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, timeout: 45),
            launcher: launcher
        )

        let error = await #expect(throws: BaselineError.self) {
            _ = try await executor.execute(try makeXcodeInput(in: dir))
        }

        #expect(error == .didNotFinish(seconds: 45))
        #expect(await launcher.mutantTestRuns == 0)
    }

    @Test("Given the Xcode baseline fails without naming a test, when execute called, then the run ends with runFailed")
    func unnamedBaselineFailureEndsRun() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let output = "Testing started\nthe test runner exited before it could report"
        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            launcher: XcodeBaselineOutcomeMock(exitCode: 65, output: output)
        )

        let error = await #expect(throws: BaselineError.self) {
            _ = try await executor.execute(try makeXcodeInput(in: dir))
        }

        #expect(error == .runFailed(output: output))
    }

    @Test("Given the unmutated Xcode suite passes, when execute called, then mutants are tested")
    func passingBaselineTestsMutants() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = XcodeBaselineOutcomeMock(exitCode: 0)
        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            launcher: launcher
        )

        let results = try await executor.execute(try makeXcodeInput(in: dir))

        #expect(results.map(\.status) == [.survived])
        #expect(await launcher.baselineRequests.count == 1)
        #expect(await launcher.mutantTestRuns == 1)
    }

    @Test("Given a test target and extra arguments, when the Xcode baseline runs, then it runs the mutants' tests")
    func baselineRunsTheMutantsTests() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = XcodeBaselineOutcomeMock(exitCode: 0)
        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(
                projectPath: dir.path, testTarget: "AppTests", xcodebuildArguments: ["-allowProvisioningUpdates"]
            ),
            launcher: launcher
        )

        _ = try await executor.execute(try makeXcodeInput(in: dir))

        let baseline = try #require(await launcher.baselineRequests.first)
        let mutant = try #require(await launcher.mutantRequests.first)
        #expect(Self.testSelection(of: baseline) == Self.testSelection(of: mutant))
        #expect(baseline.arguments.contains("-only-testing"))
        #expect(baseline.arguments.last == "-allowProvisioningUpdates")
    }

    @Test("Given a failed outcome whose output names no test, when checked, then the outcome's test is named")
    func theOutcomesTestIsNamedWhenTheOutputNamesNone() throws {
        let probe = BaselineProbe(configuration: makeRunnerConfiguration(), launcher: MockProcessLauncher(exitCode: 0))

        #expect(throws: BaselineError.testsFailed(tests: ["AppTests.testBar"])) {
            try probe.requirePassing(.testsFailed(failingTest: "AppTests.testBar"), output: "** TEST FAILED **")
        }
    }

    // MARK: - Private

    private func makeXcodeInput(in dir: URL) throws -> RunnerInput {
        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        return makeRunnerInput(
            projectPath: dir.path,
            schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
            mutants: [makeMutantDescriptor(id: "m0", filePath: sourceFile.path, isSchematizable: true)]
        )
    }

    private static func testSelection(of request: ProcessRequest) -> [String] {
        request.arguments.enumerated().compactMap { index, argument in
            ["-destination", "-only-testing"].contains(request.arguments[max(0, index - 1)]) ? argument : nil
        }
    }
}

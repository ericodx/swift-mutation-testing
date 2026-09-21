import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("Baseline validation")
struct BaselineValidationTests {

    @Test("Given baseline suite reports failing tests, when execute called, then run ends naming them")
    func failingBaselineEndsRunNamingTests() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            launcher: SPMBaselineOutcomeMock(
                exitCode: 1,
                output: """
                    Test Case '-[FooTests testBar]' failed (0.001 seconds).
                    Test Case '-[FooTests testBaz]' failed (0.002 seconds).
                    """
            )
        )
        let input = try makeSPMInput(in: dir)

        let error = await #expect(throws: BaselineError.self) {
            _ = try await executor.execute(input)
        }

        #expect(error == .testsFailed(tests: ["FooTests.testBar", "FooTests.testBaz"]))
    }

    @Test("Given baseline suite fails, when execute called, then no mutant is tested")
    func failingBaselineTestsNoMutant() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = SPMBaselineOutcomeMock(
            exitCode: 1,
            output: "Test Case '-[FooTests testBar]' failed (0.001 seconds)."
        )
        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            launcher: launcher
        )
        let input = try makeSPMInput(in: dir)

        await #expect(throws: BaselineError.self) {
            _ = try await executor.execute(input)
        }

        #expect(await launcher.mutantTestRuns == 0)
    }

    @Test("Given baseline suite does not finish, when execute called, then run ends with didNotFinish")
    func timedOutBaselineEndsRun() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm, timeout: 45),
            launcher: SPMBaselineOutcomeMock(exitCode: -1, output: "Test Suite 'All tests' started")
        )
        let input = try makeSPMInput(in: dir)

        let error = await #expect(throws: BaselineError.self) {
            _ = try await executor.execute(input)
        }

        #expect(error == .didNotFinish(seconds: 45))
    }

    @Test("Given baseline fails without naming a test, when execute called, then run ends with runFailed")
    func unnamedBaselineFailureEndsRun() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let output = "Test Suite 'All tests' started\nthe test runner stopped responding"
        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            launcher: SPMBaselineOutcomeMock(exitCode: 1, output: output)
        )
        let input = try makeSPMInput(in: dir)

        let error = await #expect(throws: BaselineError.self) {
            _ = try await executor.execute(input)
        }

        #expect(error == .runFailed(output: output))
    }

    @Test("Given baseline suite passes, when execute called, then mutants are tested")
    func passingBaselineTestsMutants() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let launcher = SPMBaselineOutcomeMock(exitCode: 0)
        let executor = MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            launcher: launcher
        )
        let input = try makeSPMInput(in: dir)

        let results = try await executor.execute(input)

        #expect(results.count == 1)
        #expect(results[0].status == .survived)
        #expect(await launcher.mutantTestRuns == 1)
    }

    // MARK: - Private

    private func makeSPMInput(in dir: URL) throws -> RunnerInput {
        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let x = false"
        )

        return makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
            mutants: [mutant]
        )
    }
}

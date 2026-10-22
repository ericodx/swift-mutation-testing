import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("MutantExecutor — confirming kills made in parallel")
struct MutantExecutorKillConfirmationTests {
    private static let otherKill: (exitCode: Int32, output: String) = (
        1, "✘ Test roundTripsAFixtureFile() failed after 0.2 seconds with 1 issue."
    )
    private static let otherFilter = #"roundTripsAFixtureFile\(\)"#

    @Test("Given a kill outside the file's suite that the killing test does not repeat alone, then the suite decides")
    func aKillTheKillingTestDoesNotRepeatIsDecidedAlone() async throws {
        let launcher = FilterScriptLauncher(outcomes: ["": [Self.otherKill]])

        let results = try await execute(launcher: launcher, concurrency: 2)

        #expect(results.map(\.status) == [.survived])
        #expect(await launcher.filters == ["FooTests", nil, Self.otherFilter, "FooTests", nil])
    }

    @Test("Given a kill outside the file's suite that the killing test repeats alone, then it stays a kill")
    func aKillTheKillingTestRepeatsIsKept() async throws {
        let launcher = FilterScriptLauncher(outcomes: ["": [Self.otherKill], Self.otherFilter: [Self.otherKill]])

        let results = try await execute(launcher: launcher, concurrency: 2)

        #expect(results.map(\.status) == [.killed(by: "roundTripsAFixtureFile()")])
        #expect(results.map(\.activated) == [true])
        #expect(await launcher.filters == ["FooTests", nil, Self.otherFilter])
    }

    @Test("Given a kill by a test that cannot be named in a filter, when confirmed, then the suite runs alone")
    func aKillerWithoutAFilterIsConfirmedByTheSuite() async throws {
        let display: (exitCode: Int32, output: String) = (
            1, #"✘ Test "a check" failed after 0.1 seconds with 1 issue."#
        )
        let launcher = FilterScriptLauncher(outcomes: ["": [display, display]])

        let results = try await execute(launcher: launcher, concurrency: 2)

        #expect(results.map(\.status) == [.killed(by: "a check")])
        #expect(await launcher.filters == ["FooTests", nil, "FooTests", nil])
    }

    @Test("Given a kill by the file's own suite, when executed in parallel, then it is not confirmed")
    func aKillByTheFilesSuiteIsTrusted() async throws {
        let launcher = FilterScriptLauncher(outcomes: ["FooTests": [Self.otherKill]])

        let results = try await execute(launcher: launcher, concurrency: 2)

        #expect(results.map(\.status) == [.killed(by: "roundTripsAFixtureFile()")])
        #expect(await launcher.filters == ["FooTests"])
    }

    @Test("Given one worker, when a kill comes from outside the file's suite, then it is not confirmed")
    func oneWorkerConfirmsNothing() async throws {
        let launcher = FilterScriptLauncher(outcomes: ["": [Self.otherKill]])

        let results = try await execute(launcher: launcher, concurrency: 1)

        #expect(results.map(\.status) == [.killed(by: "roundTripsAFixtureFile()")])
        #expect(await launcher.filters == ["FooTests", nil])
    }

    // MARK: - Helpers

    private func execute(launcher: FilterScriptLauncher, concurrency: Int) async throws -> [ExecutionResult] {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)
        let tests = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try "@Suite struct FooTests {}".write(
            to: tests.appendingPathComponent("FooTests.swift"), atomically: true, encoding: .utf8
        )

        return try await MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm, concurrency: concurrency),
            launcher: launcher
        ).execute(
            makeRunnerInput(
                projectPath: dir.path,
                projectType: .spm,
                schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
                mutants: [makeMutantDescriptor(id: "m0", filePath: sourceFile.path, isSchematizable: true)]
            )
        )
    }
}

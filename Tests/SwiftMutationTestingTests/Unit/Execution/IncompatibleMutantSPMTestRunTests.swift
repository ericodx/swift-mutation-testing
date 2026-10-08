import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("IncompatibleMutantExecutor — SPM test runs")
struct IncompatibleMutantSPMTestRunTests {
    @Test("Given a survivor whose file has its own suite, when tested, then that suite runs first, both stopping early")
    func theOwnSuiteRunsFirstAndBothStopAtTheFirstFailure() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let launcher = CountingLauncher(wrapping: MockProcessLauncher(exitCode: 0))

        let results = try await run(in: dir, launcher: launcher, testTarget: "AppTests")

        let tests = await testRequests(of: launcher)
        #expect(results.first?.status == .survived)
        #expect(tests.map(filter(of:)) == ["FooTests", "AppTests"])
        #expect(tests.allSatisfy { $0.stopRule == .firstTestFailure })
    }

    @Test("Given a mutant its own suite kills, when tested, then the whole suite never runs")
    func aKillInTheOwnSuiteSkipsTheFullRun() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let launcher = CountingLauncher(
            wrapping: SPMBuildSuccessTestFailureMock(failureOutput: #"Test "myTest" failed after 0.001 seconds."#)
        )

        let results = try await run(in: dir, launcher: launcher, testTarget: nil)

        #expect(results.first?.status == .killed(by: "myTest"))
        #expect(await testRequests(of: launcher).map(filter(of:)) == ["FooTests"])
    }

    @Test("Given a reproduction, when tested, then only the whole suite runs, to its end")
    func aReproductionRunsTheWholeSuiteToItsEnd() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        let reproduction = Reproduction()
        defer {
            for path in reproduction.keptSandboxes { try? FileManager.default.removeItem(atPath: path) }
            FileHelpers.cleanup(dir)
        }
        let launcher = CountingLauncher(wrapping: MockProcessLauncher(exitCode: 0))

        _ = try await run(in: dir, launcher: launcher, testTarget: nil, reproduction: reproduction)

        let tests = await testRequests(of: launcher)
        #expect(tests.map(filter(of:)) == [nil])
        #expect(tests.first?.stopRule == nil)
    }

    @Test("Given an SPM mutant whose file lies outside the project, when executed, then it is unviable")
    func anSPMMutantOutsideTheProjectIsUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let launcher = CountingLauncher(wrapping: MockProcessLauncher(exitCode: 0))
        let executor = makeIncompatibleMutantExecutorSPM(in: dir, launcher: launcher)
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let results = try await executor.execute(
            [makeMutantDescriptor(filePath: "/elsewhere/Foo.swift", mutatedSourceContent: "let x = 1")],
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            pool: pool
        )

        #expect(results.map(\.status) == [.unviable])
        #expect(await testRequests(of: launcher).isEmpty)
    }

    @Test("Given an SPM test run that throws, when executed, then the error ends the pass")
    func aThrowingSPMRunEndsThePass() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        await #expect(throws: CocoaError.self) {
            _ = try await run(in: dir, launcher: ThrowingDuringTestMock(throwingOnTestCall: 1), testTarget: nil)
        }
    }

    // MARK: - Private

    private func run(
        in dir: URL, launcher: any ProcessLaunching, testTarget: String?, reproduction: Reproduction? = nil
    ) async throws -> [ExecutionResult] {
        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)
        var deps = makeExecutionDeps(launcher: launcher, cacheStorePath: dir.appendingPathComponent("c.json").path)
        deps.targetedSuites = ["FooTests": TargetedSuite(name: "FooTests", testTarget: "AppTests")]
        let executor = IncompatibleMutantExecutor(deps: deps, sandboxFactory: SandboxFactory())
        var configuration = makeRunnerConfiguration(projectPath: dir.path, projectType: .spm, testTarget: testTarget)
        configuration.build.reproduction = reproduction
        let pool = makeSimulatorPool()
        try await pool.setUp()

        return try await executor.execute(
            [makeMutantDescriptor(filePath: sourceFile.path, mutatedSourceContent: "let x = false")],
            configuration: configuration,
            pool: pool
        )
    }

    private func testRequests(of launcher: CountingLauncher) async -> [ProcessRequest] {
        await launcher.requests.filter { $0.arguments.first == "test" }
    }

    private func filter(of request: ProcessRequest) -> String? {
        guard let index = request.arguments.firstIndex(of: "--filter") else { return nil }
        return request.arguments[index + 1]
    }
}

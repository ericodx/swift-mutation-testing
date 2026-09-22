import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("IncompatibleMutantExecutor")
struct IncompatibleMutantExecutorTests {
    @Test("Given 3 mutants with content, when execute called, then 3 results are returned in order")
    func executeReturnsAllResultsInOrder() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let executor = makeIncompatibleMutantExecutor(in: dir, exitCode: 1)
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutants = (0 ..< 3).map {
            makeMutantDescriptor(
                id: "m\($0)",
                originalText: "a + b",
                mutatedText: "a - b",
                operatorIdentifier: "binaryOperator",
                description: "Replace + with -",
                mutatedSourceContent: "let x = \($0)",
                sourceContentHash: "test-hash"
            )
        }

        let results = try await executor.execute(
            mutants,
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            pool: pool
        )

        #expect(results.count == 3)
        #expect(results.map(\.descriptor.id) == ["m0", "m1", "m2"])
    }

    @Test("Given mutant without content, when execute called, then returns unviable without building")
    func nilContentReturnsUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let executor = makeIncompatibleMutantExecutor(in: dir, exitCode: 0)
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: nil,
            sourceContentHash: "test-hash"
        )

        let results = try await executor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            pool: pool
        )

        #expect(results.first?.status == .unviable)
    }

    @Test("Given build failure, when execute called, then returns unviable")
    func buildFailureReturnsUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let executor = makeIncompatibleMutantExecutor(in: dir, exitCode: 1)
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: "let x = 1",
            sourceContentHash: "test-hash"
        )

        let results = try await executor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            pool: pool
        )

        #expect(results.first?.status == .unviable)
    }

    @Test("Given noCache, when a mutant is already cached, then it is retested rather than replayed")
    func noCacheStoreRetestsCachedMutant() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let storePath = dir.appendingPathComponent("cache.json").path
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: "let x = 1",
            sourceContentHash: "test-hash"
        )
        let configuration = makeRunnerConfiguration(projectPath: dir.path)

        let cached = try await execute(
            mutant, in: dir, storePath: storePath, noCache: false,
            launcher: MockProcessLauncher(exitCode: 1), configuration: configuration, pool: pool
        )
        #expect(cached.first?.status == .unviable)

        // The launcher now succeeds, so a replayed verdict and a fresh one differ.
        let fresh = try await execute(
            mutant, in: dir, storePath: storePath, noCache: true,
            launcher: MockProcessLauncher(exitCode: 0), configuration: configuration, pool: pool
        )

        #expect(fresh.first?.status == .survived)
    }

    private func execute(
        _ mutant: MutantDescriptor,
        in dir: URL,
        storePath: String,
        noCache: Bool,
        launcher: any ProcessLaunching,
        configuration: RunnerConfiguration,
        pool: SimulatorPool
    ) async throws -> [ExecutionResult] {
        let store = CacheStore(storePath: storePath, noCache: noCache)
        try await store.load()

        let executor = IncompatibleMutantExecutor(
            deps: ExecutionDeps(
                launcher: launcher,
                cacheStore: store,
                reporter: MockProgressReporter(),
                counter: MutationCounter(total: 1),
                killerTestFileResolver: KillerTestFileResolver(testFilePaths: [], projectPath: "/tmp")
            ),
            sandboxFactory: SandboxFactory()
        )

        let results = try await executor.execute([mutant], configuration: configuration, pool: pool)
        try await store.persist()
        return results
    }

    @Test("Given configuration with testTarget, when execute called, then testTarget is applied")
    func configurationWithTestTargetExecutesSuccessfully() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let pool = makeSimulatorPool()
        try await pool.setUp()
        let config = makeRunnerConfiguration(projectPath: dir.path, testTarget: "AppTests")
        let executor = IncompatibleMutantExecutor(
            deps: makeExecutionDeps(
                launcher: MockProcessLauncher(exitCode: 1),
                cacheStorePath: dir.appendingPathComponent("cache.json").path
            ),
            sandboxFactory: SandboxFactory()
        )

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: "let x = 1",
            sourceContentHash: "test-hash"
        )

        let results = try await executor.execute(
            [mutant],
            configuration: config,
            pool: pool
        )
        #expect(results.count == 1)
    }

    @Test("Given mutant already in cache, when execute called again with invalid path, then returns cached result")
    func cachedMutantReturnsCachedStatus() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let cacheStore = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: "let x = 1",
            sourceContentHash: "test-hash"
        )

        let firstExecutor = IncompatibleMutantExecutor(
            deps: ExecutionDeps(
                launcher: MockProcessLauncher(exitCode: 1),
                cacheStore: cacheStore,
                reporter: MockProgressReporter(),
                counter: MutationCounter(total: 1),
                killerTestFileResolver: KillerTestFileResolver(testFilePaths: [], projectPath: "/tmp")
            ),
            sandboxFactory: SandboxFactory()
        )
        _ = try await firstExecutor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            pool: pool
        )

        let secondExecutor = IncompatibleMutantExecutor(
            deps: ExecutionDeps(
                launcher: MockProcessLauncher(exitCode: 1),
                cacheStore: cacheStore,
                reporter: MockProgressReporter(),
                counter: MutationCounter(total: 1),
                killerTestFileResolver: KillerTestFileResolver(testFilePaths: [], projectPath: "/tmp")
            ),
            sandboxFactory: SandboxFactory()
        )
        let results = try await secondExecutor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: "/non/existent/path"),
            pool: pool
        )

        #expect(results.first?.status == .unviable)
    }

    @Test("Given launcher throws during test run, when execute called, then error is propagated")
    func launchThrowsPropagatesError() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let executor = IncompatibleMutantExecutor(
            deps: makeExecutionDeps(
                launcher: MockProcessLauncher(exitCode: 0, throwsOnCapture: true),
                cacheStorePath: dir.appendingPathComponent("cache.json").path
            ),
            sandboxFactory: SandboxFactory()
        )
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: "let x = 1",
            sourceContentHash: "test-hash"
        )

        await #expect(throws: (any Error).self) {
            try await executor.execute(
                [mutant],
                configuration: makeRunnerConfiguration(projectPath: dir.path),
                pool: pool
            )
        }
    }

    @Test("Given SPM project type and exit code 0, when execute called, then mutant survived")
    func spmExitCodeZeroProducesSurvivedStatus() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let executor = makeIncompatibleMutantExecutorSPM(in: dir, launcher: MockProcessLauncher(exitCode: 0))
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: "let x = 1",
            sourceContentHash: "test-hash"
        )

        let results = try await executor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            pool: pool
        )

        #expect(results.first?.status == .survived)
    }

    @Test("Given SPM project type and mutant without content, when execute called, then it is unviable")
    func spmNilContentMutantIsUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let executor = makeIncompatibleMutantExecutorSPM(in: dir, launcher: MockProcessLauncher(exitCode: 0))
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: nil,
            sourceContentHash: "test-hash"
        )

        let results = try await executor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            pool: pool
        )

        #expect(results.count == 1)
        #expect(results.first?.status == .unviable)
    }

    @Test("Given SPM project type and both a content-less and a viable mutant, when execute called, then both report")
    func spmNilContentMutantDoesNotBlockViableOne() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let executor = makeIncompatibleMutantExecutorSPM(in: dir, launcher: MockProcessLauncher(exitCode: 0))
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let withoutContent = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: nil,
            sourceContentHash: "test-hash"
        )
        let withContent = makeMutantDescriptor(
            id: "m1",
            filePath: sourceFile.path,
            originalText: "a + b",
            mutatedText: "a * b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with *",
            mutatedSourceContent: "let x = 1",
            sourceContentHash: "test-hash"
        )

        let results = try await executor.execute(
            [withoutContent, withContent],
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            pool: pool
        )

        #expect(results.count == 2)
        #expect(results.first(where: { $0.descriptor.id == "m0" })?.status == .unviable)
        #expect(results.first(where: { $0.descriptor.id == "m1" })?.status == .survived)
    }

    @Test("Given keep-logs, when a mutant is unviable, then the failing build's output is written")
    func unviableMutantWritesItsBuildOutput() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)
        let logs = dir.appendingPathComponent("logs")

        let executor = makeIncompatibleMutantExecutorSPM(
            in: dir,
            launcher: MockProcessLauncher(exitCode: 1, output: "error: cannot convert value of type")
        )
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let results = try await executor.execute(
            [makeMutantDescriptor(id: "m0", filePath: sourceFile.path, mutatedSourceContent: "let x = 1")],
            configuration: makeRunnerConfiguration(
                projectPath: dir.path, projectType: .spm, keepLogsPath: logs.path
            ),
            pool: pool
        )

        #expect(results.first?.status == .unviable)

        // Unviable says a mutant was not testable without saying why; the build output is the why.
        let log = try String(contentsOf: logs.appendingPathComponent("m0.log"), encoding: .utf8)
        #expect(log.contains("Unviable"))
        #expect(log.contains("error: cannot convert value of type"))
    }

    @Test("Given keep-logs and a mutation that could not be applied, when execute called, then the log says so")
    func unappliedMutationSaysSoInTheLog() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let logs = dir.appendingPathComponent("logs")
        let executor = makeIncompatibleMutantExecutorSPM(in: dir, launcher: MockProcessLauncher(exitCode: 0))
        let pool = makeSimulatorPool()
        try await pool.setUp()

        _ = try await executor.execute(
            [makeMutantDescriptor(id: "m0", mutatedSourceContent: nil)],
            configuration: makeRunnerConfiguration(
                projectPath: dir.path, projectType: .spm, keepLogsPath: logs.path
            ),
            pool: pool
        )

        let log = try String(contentsOf: logs.appendingPathComponent("m0.log"), encoding: .utf8)
        #expect(log.contains("could not be applied"))
    }

    @Test("Given SPM project type and exit code 1 with failure output, when execute called, then mutant is killed")
    func spmExitCodeOneWithFailureOutputProducesKilledStatus() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let output = #"Test "myTest" failed after 0.001 seconds."#
        let executor = makeIncompatibleMutantExecutorSPM(
            in: dir, launcher: SPMBuildSuccessTestFailureMock(failureOutput: output))
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: "let x = 1",
            sourceContentHash: "test-hash"
        )

        let results = try await executor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            pool: pool
        )

        #expect(results.first?.status == .killed(by: "myTest"))
    }

    @Test("Given SPM project type and initial build failure, when execute called, then all viable mutants are unviable")
    func spmInitialBuildFailureMarksAllUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let executor = makeIncompatibleMutantExecutorSPM(in: dir, launcher: MockProcessLauncher(exitCode: 1))
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutants = [
            makeMutantDescriptor(
                id: "m0",
                filePath: sourceFile.path,
                originalText: "a + b",
                mutatedText: "a - b",
                operatorIdentifier: "binaryOperator",
                description: "Replace + with -",
                mutatedSourceContent: "let x = false",
                sourceContentHash: "test-hash"
            ),
            makeMutantDescriptor(
                id: "m1",
                filePath: sourceFile.path,
                originalText: "a + b",
                mutatedText: "a - b",
                operatorIdentifier: "binaryOperator",
                description: "Replace + with -",
                mutatedSourceContent: "let x = 0",
                sourceContentHash: "test-hash"
            ),
        ]

        let results = try await executor.execute(
            mutants,
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            pool: pool
        )

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.status == .unviable })
    }

    @Test("Given SPM project type with testTarget, when execute called, then filter is applied")
    func spmTestTargetFilterIsApplied() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let output = #"Test "myTest" failed after 0.001 seconds."#
        let executor = makeIncompatibleMutantExecutorSPM(
            in: dir, launcher: SPMBuildSuccessTestFailureMock(failureOutput: output))
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let config = makeRunnerConfiguration(
            projectPath: dir.path,
            projectType: .spm,
            testTarget: "FooTests"
        )

        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: "let x = 1",
            sourceContentHash: "test-hash"
        )

        let results = try await executor.execute(
            [mutant],
            configuration: config,
            pool: pool
        )

        #expect(results.count == 1)
    }

    @Test("Given SPM project type and per-mutant build failure, when execute called, then mutant is unviable")
    func spmPerMutantBuildFailureReturnsUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let executor = makeIncompatibleMutantExecutorSPM(
            in: dir, launcher: SPMInitialBuildSuccessThenFailMock())
        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            description: "Replace + with -",
            mutatedSourceContent: "let x = INVALID",
            sourceContentHash: "test-hash"
        )

        let results = try await executor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            pool: pool
        )

        #expect(results.first?.status == .unviable)
    }
}

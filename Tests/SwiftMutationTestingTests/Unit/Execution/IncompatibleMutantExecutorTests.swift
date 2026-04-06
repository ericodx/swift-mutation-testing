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
                mutatedSourceContent: "let x = \($0)"
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
            mutatedSourceContent: nil
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
            mutatedSourceContent: "let x = 1"
        )

        let results = try await executor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            pool: pool
        )

        #expect(results.first?.status == .unviable)
    }

    @Test("Given noCache is true, when mutant already cached, then cache is bypassed")
    func noCacheConfigurationBypassesCache() async throws {
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
            mutatedSourceContent: "let x = 1"
        )

        let firstExecutor = IncompatibleMutantExecutor(
            deps: ExecutionDeps(
                launcher: MockProcessLauncher(exitCode: 1),
                cacheStore: cacheStore,
                reporter: MockProgressReporter(),
                counter: MutationCounter(total: 1),
                killerTestFileResolver: KillerTestFileResolver(testFilePaths: [])
            ),
            sandboxFactory: SandboxFactory()
        )
        _ = try await firstExecutor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: dir.path),
            pool: pool
        )

        let noCacheConfig = makeRunnerConfiguration(projectPath: dir.path, noCache: true)
        let secondExecutor = IncompatibleMutantExecutor(
            deps: ExecutionDeps(
                launcher: MockProcessLauncher(exitCode: 1),
                cacheStore: cacheStore,
                reporter: MockProgressReporter(),
                counter: MutationCounter(total: 1),
                killerTestFileResolver: KillerTestFileResolver(testFilePaths: [])
            ),
            sandboxFactory: SandboxFactory()
        )
        let results = try await secondExecutor.execute(
            [mutant],
            configuration: noCacheConfig,
            pool: pool
        )

        #expect(results.first?.status == .unviable)
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
            mutatedSourceContent: "let x = 1"
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
            mutatedSourceContent: "let x = 1"
        )

        let firstExecutor = IncompatibleMutantExecutor(
            deps: ExecutionDeps(
                launcher: MockProcessLauncher(exitCode: 1),
                cacheStore: cacheStore,
                reporter: MockProgressReporter(),
                counter: MutationCounter(total: 1),
                killerTestFileResolver: KillerTestFileResolver(testFilePaths: [])
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
                killerTestFileResolver: KillerTestFileResolver(testFilePaths: [])
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
            mutatedSourceContent: "let x = 1"
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
            mutatedSourceContent: "let x = 1"
        )

        let results = try await executor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            pool: pool
        )

        #expect(results.first?.status == .survived)
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
            mutatedSourceContent: "let x = 1"
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
                mutatedSourceContent: "let x = false"
            ),
            makeMutantDescriptor(
                id: "m1",
                filePath: sourceFile.path,
                originalText: "a + b",
                mutatedText: "a - b",
                operatorIdentifier: "binaryOperator",
                description: "Replace + with -",
                mutatedSourceContent: "let x = 0"
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
            mutatedSourceContent: "let x = 1"
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
            mutatedSourceContent: "let x = INVALID"
        )

        let results = try await executor.execute(
            [mutant],
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            pool: pool
        )

        #expect(results.first?.status == .unviable)
    }
}

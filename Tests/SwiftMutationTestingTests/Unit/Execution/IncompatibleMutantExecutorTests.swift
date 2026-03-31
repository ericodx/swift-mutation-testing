import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("IncompatibleMutantExecutor")
struct IncompatibleMutantExecutorTests {
    @Test("Given 3 mutants with content, when execute called, then 3 results are returned in order")
    func executeReturnsAllResultsInOrder() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let executor = makeExecutor(in: dir, exitCode: 1)
        let pool = makePool()
        try await pool.setUp()

        let mutants = (0 ..< 3).map { makeMutant(id: "m\($0)", content: "let x = \($0)") }

        let results = try await executor.execute(
            mutants,
            configuration: makeConfiguration(projectPath: dir.path),
            pool: pool,
            testFilesHash: "hash"
        )

        #expect(results.count == 3)
        #expect(results.map(\.descriptor.id) == ["m0", "m1", "m2"])
    }

    @Test("Given mutant without content, when execute called, then returns unviable without building")
    func nilContentReturnsUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let executor = makeExecutor(in: dir, exitCode: 0)
        let pool = makePool()
        try await pool.setUp()

        let mutant = makeMutant(id: "m0", content: nil)

        let results = try await executor.execute(
            [mutant],
            configuration: makeConfiguration(projectPath: dir.path),
            pool: pool,
            testFilesHash: "hash"
        )

        #expect(results.first?.status == .unviable)
    }

    @Test("Given build failure, when execute called, then returns unviable")
    func buildFailureReturnsUnviable() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let executor = makeExecutor(in: dir, exitCode: 1)
        let pool = makePool()
        try await pool.setUp()

        let mutant = makeMutant(id: "m0", content: "let x = 1")

        let results = try await executor.execute(
            [mutant],
            configuration: makeConfiguration(projectPath: dir.path),
            pool: pool,
            testFilesHash: "hash"
        )

        #expect(results.first?.status == .unviable)
    }

    @Test("Given noCache is true, when mutant already cached, then cache is bypassed")
    func noCacheConfigurationBypassesCache() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let cacheStore = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let pool = makePool()
        try await pool.setUp()

        let mutant = makeMutant(id: "m0", content: "let x = 1")

        let firstExecutor = IncompatibleMutantExecutor(
            launcher: MockProcessLauncher(exitCode: 1),
            sandboxFactory: SandboxFactory(),
            cacheStore: cacheStore,
            reporter: MockProgressReporter(),
            counter: MutationCounter(total: 1)
        )
        _ = try await firstExecutor.execute(
            [mutant],
            configuration: makeConfiguration(projectPath: dir.path),
            pool: pool,
            testFilesHash: "hash"
        )

        let noCacheConfig = RunnerConfiguration(
            projectPath: dir.path,
            build: .init(
                projectType: .xcode(scheme: "MyScheme", destination: "platform=macOS"),
                timeout: 60, concurrency: 1, noCache: true),
            reporting: .init(quiet: true),
            filter: .init(excludePatterns: [], operators: [])
        )
        let secondExecutor = IncompatibleMutantExecutor(
            launcher: MockProcessLauncher(exitCode: 1),
            sandboxFactory: SandboxFactory(),
            cacheStore: cacheStore,
            reporter: MockProgressReporter(),
            counter: MutationCounter(total: 1)
        )
        let results = try await secondExecutor.execute(
            [mutant],
            configuration: noCacheConfig,
            pool: pool,
            testFilesHash: "hash"
        )

        #expect(results.first?.status == .unviable)
    }

    @Test("Given configuration with testTarget, when execute called, then testTarget is applied")
    func configurationWithTestTargetExecutesSuccessfully() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let pool = makePool()
        try await pool.setUp()
        let config = RunnerConfiguration(
            projectPath: dir.path,
            build: .init(
                projectType: .xcode(scheme: "MyScheme", destination: "platform=macOS"),
                testTarget: "AppTests", timeout: 60, concurrency: 1, noCache: false),
            reporting: .init(quiet: true),
            filter: .init(excludePatterns: [], operators: [])
        )
        let executor = IncompatibleMutantExecutor(
            launcher: MockProcessLauncher(exitCode: 1),
            sandboxFactory: SandboxFactory(),
            cacheStore: CacheStore(storePath: dir.appendingPathComponent("cache.json").path),
            reporter: MockProgressReporter(),
            counter: MutationCounter(total: 1)
        )

        let results = try await executor.execute(
            [makeMutant(id: "m0", content: "let x = 1")],
            configuration: config,
            pool: pool,
            testFilesHash: "hash"
        )
        #expect(results.count == 1)
    }

    @Test("Given mutant already in cache, when execute called again with invalid path, then returns cached result")
    func cachedMutantReturnsCachedStatus() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let cacheStore = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let pool = makePool()
        try await pool.setUp()

        let mutant = makeMutant(id: "m0", content: "let x = 1")

        let firstExecutor = IncompatibleMutantExecutor(
            launcher: MockProcessLauncher(exitCode: 1),
            sandboxFactory: SandboxFactory(),
            cacheStore: cacheStore,
            reporter: MockProgressReporter(),
            counter: MutationCounter(total: 1)
        )
        _ = try await firstExecutor.execute(
            [mutant],
            configuration: makeConfiguration(projectPath: dir.path),
            pool: pool,
            testFilesHash: "hash"
        )

        let secondExecutor = IncompatibleMutantExecutor(
            launcher: MockProcessLauncher(exitCode: 1),
            sandboxFactory: SandboxFactory(),
            cacheStore: cacheStore,
            reporter: MockProgressReporter(),
            counter: MutationCounter(total: 1)
        )
        let results = try await secondExecutor.execute(
            [mutant],
            configuration: makeConfiguration(projectPath: "/non/existent/path"),
            pool: pool,
            testFilesHash: "hash"
        )

        #expect(results.first?.status == .unviable)
    }

    @Test("Given launcher throws during test run, when execute called, then error is propagated")
    func launchThrowsPropagatesError() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let executor = IncompatibleMutantExecutor(
            launcher: MockProcessLauncher(exitCode: 0, throwsOnCapture: true),
            sandboxFactory: SandboxFactory(),
            cacheStore: CacheStore(storePath: dir.appendingPathComponent("cache.json").path),
            reporter: MockProgressReporter(),
            counter: MutationCounter(total: 1)
        )
        let pool = makePool()
        try await pool.setUp()

        await #expect(throws: (any Error).self) {
            try await executor.execute(
                [makeMutant(id: "m0", content: "let x = 1")],
                configuration: makeConfiguration(projectPath: dir.path),
                pool: pool,
                testFilesHash: "hash"
            )
        }
    }

    @Test("Given SPM project type and exit code 0, when execute called, then mutant survived")
    func spmExitCodeZeroProducesSurvivedStatus() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let executor = makeExecutorSPM(in: dir, exitCode: 0)
        let pool = makePool()
        try await pool.setUp()

        let results = try await executor.execute(
            [makeMutant(id: "m0", content: "let x = 1")],
            configuration: makeConfigurationSPM(projectPath: dir.path),
            pool: pool,
            testFilesHash: "hash"
        )

        #expect(results.first?.status == .survived)
    }

    @Test("Given SPM project type and exit code 1 with failure output, when execute called, then mutant is killed")
    func spmExitCodeOneWithFailureOutputProducesKilledStatus() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let output = #"Test "myTest" failed after 0.001 seconds."#
        let executor = makeExecutorSPM(in: dir, exitCode: 1, output: output)
        let pool = makePool()
        try await pool.setUp()

        let results = try await executor.execute(
            [makeMutant(id: "m0", content: "let x = 1")],
            configuration: makeConfigurationSPM(projectPath: dir.path),
            pool: pool,
            testFilesHash: "hash"
        )

        #expect(results.first?.status == .killed(by: "myTest"))
    }

    private func makeExecutorSPM(
        in dir: URL,
        exitCode: Int32,
        output: String = ""
    ) -> IncompatibleMutantExecutor {
        IncompatibleMutantExecutor(
            launcher: MockProcessLauncher(exitCode: exitCode, output: output),
            sandboxFactory: SandboxFactory(),
            cacheStore: CacheStore(storePath: dir.appendingPathComponent("cache.json").path),
            reporter: MockProgressReporter(),
            counter: MutationCounter(total: 1)
        )
    }

    private func makeConfigurationSPM(projectPath: String) -> RunnerConfiguration {
        RunnerConfiguration(
            projectPath: projectPath,
            build: .init(projectType: .spm, timeout: 60, concurrency: 1, noCache: false),
            reporting: .init(quiet: true),
            filter: .init(excludePatterns: [], operators: [])
        )
    }

    private func makeExecutor(in dir: URL, exitCode: Int32) -> IncompatibleMutantExecutor {
        IncompatibleMutantExecutor(
            launcher: MockProcessLauncher(exitCode: exitCode),
            sandboxFactory: SandboxFactory(),
            cacheStore: CacheStore(storePath: dir.appendingPathComponent("cache.json").path),
            reporter: MockProgressReporter(),
            counter: MutationCounter(total: 3)
        )
    }

    private func makePool() -> SimulatorPool {
        SimulatorPool(
            baseUDID: nil, size: 1,
            destination: "platform=macOS", launcher: MockProcessLauncher(exitCode: 0)
        )
    }

    private func makeConfiguration(projectPath: String) -> RunnerConfiguration {
        RunnerConfiguration(
            projectPath: projectPath,
            build: .init(
                projectType: .xcode(scheme: "MyScheme", destination: "platform=macOS"),
                timeout: 60, concurrency: 1, noCache: false),
            reporting: .init(quiet: true),
            filter: .init(excludePatterns: [], operators: [])
        )
    }

    private func makeMutant(id: String, content: String?) -> MutantDescriptor {
        MutantDescriptor(
            id: id,
            filePath: "/tmp/Foo.swift",
            line: 1,
            column: 1,
            utf8Offset: 0,
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            replacementKind: .binaryOperator,
            description: "Replace + with -",
            isSchematizable: false,
            mutatedSourceContent: content
        )
    }
}

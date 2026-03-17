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

    @Test("Given mutant already in cache, when execute called again with invalid path, then returns cached result")
    func cachedMutantReturnsCachedStatus() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let cacheStore = CacheStore(cacheURL: dir.appendingPathComponent("cache.json"))
        let pool = makePool()
        try await pool.setUp()

        let mutant = makeMutant(id: "m0", content: "let x = 1")

        let firstExecutor = IncompatibleMutantExecutor(
            launcher: MockProcessLauncher(exitCode: 1),
            sandboxFactory: SandboxFactory(),
            cacheStore: cacheStore,
            reporter: MockProgressReporter()
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
            reporter: MockProgressReporter()
        )
        let results = try await secondExecutor.execute(
            [mutant],
            configuration: makeConfiguration(projectPath: "/non/existent/path"),
            pool: pool,
            testFilesHash: "hash"
        )

        #expect(results.first?.status == .unviable)
    }

    private func makeExecutor(in dir: URL, exitCode: Int32) -> IncompatibleMutantExecutor {
        IncompatibleMutantExecutor(
            launcher: MockProcessLauncher(exitCode: exitCode),
            sandboxFactory: SandboxFactory(),
            cacheStore: CacheStore(cacheURL: dir.appendingPathComponent("cache.json")),
            reporter: MockProgressReporter()
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
            scheme: "MyScheme",
            destination: "platform=macOS",
            testTarget: nil,
            timeout: 60,
            concurrency: 1,
            noCache: false,
            output: nil,
            htmlOutput: nil,
            sonarOutput: nil,
            quiet: true
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

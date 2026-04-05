import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("FallbackExecutor")
struct FallbackExecutorTests {
    @Test("Given SPM project type with successful build, when execute called, then results are returned")
    func spmFallbackBuildSuccessReturnsResults() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let config = RunnerConfiguration(
            projectPath: dir.path,
            build: .init(projectType: .spm, timeout: 60, concurrency: 1, noCache: false),
            reporting: .init(quiet: true),
            filter: .init(excludePatterns: [], operators: [])
        )

        let launcher = MockProcessLauncher(exitCode: 0)
        let counter = MutationCounter(total: 1)
        let cacheStore = CacheStore(storePath: dir.appendingPathComponent("cache.json").path)
        let deps = ExecutionDeps(
            launcher: launcher,
            cacheStore: cacheStore,
            reporter: MockProgressReporter(),
            counter: counter
        )

        let pool = SimulatorPool(
            baseUDID: nil, size: 1,
            destination: "platform=macOS", launcher: MockProcessLauncher(exitCode: 0)
        )
        try await pool.setUp()

        let mutant = MutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            line: 1,
            column: 1,
            utf8Offset: 0,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: nil
        )

        let input = RunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            timeout: 60,
            concurrency: 1,
            noCache: false,
            schematizedFiles: [
                SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")
            ],
            supportFileContent: "",
            mutants: [mutant]
        )

        let executor = FallbackExecutor(deps: deps, configuration: config)
        let results = try await executor.execute(input: input, pool: pool, testFilesHash: "hash")

        #expect(results.count == 1)
    }
}

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

        let config = makeRunnerConfiguration(projectPath: dir.path, projectType: .spm)

        let launcher = MockProcessLauncher(exitCode: 0)
        let deps = makeExecutionDeps(
            launcher: launcher,
            cacheStorePath: dir.appendingPathComponent("cache.json").path
        )

        let pool = makeSimulatorPool()
        try await pool.setUp()

        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true
        )

        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [
                SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")
            ],
            mutants: [mutant]
        )

        let executor = FallbackExecutor(deps: deps, configuration: config)
        let results = try await executor.execute(input: input, pool: pool)

        #expect(results.count == 1)
    }
}

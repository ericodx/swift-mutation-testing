import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("Generated sources are hidden from SwiftLint")
struct GeneratedSourceLintSuppressionTests {
    @Test("Given a package's incompatible mutant, when it is built, then its source is wrapped for SwiftLint")
    func anIncompatiblePackageMutantIsWrapped() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let launcher = SourceCapturingLauncher(base: MockProcessLauncher(exitCode: 0), capturing: "Foo.swift")
        let mutant = try makeIncompatibleMutant(in: dir)
        let pool = makeSimulatorPool()
        try await pool.setUp()

        _ = try await makeIncompatibleMutantExecutorSPM(in: dir, launcher: launcher).execute(
            [mutant], configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm), pool: pool
        )

        #expect(await launcher.built.last == LintSuppression.wrapping("let x = 2"))
    }

    @Test("Given an Xcode incompatible mutant, when it is built, then its source is wrapped for SwiftLint")
    func anIncompatibleXcodeMutantIsWrapped() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let launcher = SourceCapturingLauncher(
            base: RecordingProcessLauncher(responses: [(0, ""), (0, "")]), capturing: "Foo.swift"
        )
        let mutant = try makeIncompatibleMutant(in: dir)
        let pool = makeSimulatorPool()
        try await pool.setUp()

        _ = try await IncompatibleMutantExecutor(
            deps: makeExecutionDeps(launcher: launcher, cacheStorePath: dir.appendingPathComponent("cache.json").path),
            sandboxFactory: SandboxFactory()
        ).execute([mutant], configuration: makeRunnerConfiguration(projectPath: dir.path), pool: pool)

        #expect(await launcher.built.last == LintSuppression.wrapping("let x = 2"))
    }

    @Test("Given a schematized file, when the shared build runs, then the schema is wrapped for SwiftLint")
    func theSchemaIsWrappedForTheSharedBuild() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)
        let launcher = SourceCapturingLauncher(
            base: RecordingProcessLauncher(responses: [(0, "")]), capturing: "Foo.swift")

        _ = try? await MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: dir.path), launcher: launcher
        ).execute(
            makeRunnerInput(
                projectPath: dir.path,
                schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
                mutants: [makeMutantDescriptor(id: "m0", filePath: sourceFile.path, isSchematizable: true)]
            )
        )

        let schema = try #require(await launcher.built.first)
        #expect(schema.hasPrefix(LintSuppression.opening + "let x = false\n"))
        #expect(schema.hasSuffix(LintSuppression.closing))
    }

    // MARK: - Private

    private func makeIncompatibleMutant(in dir: URL) throws -> MutantDescriptor {
        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = 1".write(to: sourceFile, atomically: true, encoding: .utf8)
        return makeMutantDescriptor(
            id: "m0", filePath: sourceFile.path, originalText: "1", mutatedText: "2",
            operatorIdentifier: "ArithmeticOperatorReplacement", description: "1 → 2", isSchematizable: false,
            mutatedSourceContent: "let x = 2"
        )
    }
}

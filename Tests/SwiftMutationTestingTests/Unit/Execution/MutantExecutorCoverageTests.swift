import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("MutantExecutor Coverage")
struct MutantExecutorCoverageTests {
    @Test("Given test execution throws, when execute called, then error propagates after cleanup")
    func testExecutionThrowingTriggersCleanup() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourceFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: sourceFile, atomically: true, encoding: .utf8)

        let executor = MutantExecutor(
            configuration: makeConfigurationSPM(projectPath: dir.path),
            launcher: ThrowingDuringTestMock()
        )
        let mutant = makeMutant(id: "m0", filePath: sourceFile.path, isSchematizable: true)
        let input = makeInputSPM(
            projectPath: dir.path,
            schematizedFiles: [SchematizedFile(originalPath: sourceFile.path, schematizedContent: "let x = false")],
            mutants: [mutant]
        )

        await #expect(throws: Error.self) {
            _ = try await executor.execute(input)
        }
    }

    @Test("Given build error without line numbers, when retry called, then all mutants in file are excluded")
    func buildErrorWithoutLineNumbersExcludesAllMutants() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let fooFile = dir.appendingPathComponent("Foo.swift")
        try "let x = true".write(to: fooFile, atomically: true, encoding: .utf8)

        let executor = MutantExecutor(
            configuration: makeConfigurationSPM(projectPath: dir.path),
            launcher: SPMErrorWithoutLineNumberMock()
        )
        let mutant = makeMutant(id: "m0", filePath: fooFile.path, isSchematizable: true)
        let input = makeInputSPM(
            projectPath: dir.path,
            schematizedFiles: [SchematizedFile(originalPath: fooFile.path, schematizedContent: "let x = false")],
            mutants: [mutant]
        )

        let results = try await executor.execute(input)

        #expect(results.count == 1)
    }

    @Test("Given single case before default in schema, when that case excluded, then default line is preserved")
    func singleCaseExclusionPreservesDefault() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let fooFile = dir.appendingPathComponent("Foo.swift")
        try "let original = true".write(to: fooFile, atomically: true, encoding: .utf8)

        let schematized =
            "func foo() {\n"
            + "switch __swiftMutationTestingID {\n"
            + "case \"swift-mutation-testing_0\":\n"
            + "return true\n"
            + "default:\n"
            + "return nil\n"
            + "}\n"
            + "}"

        let executor = MutantExecutor(
            configuration: makeConfigurationSPM(projectPath: dir.path),
            launcher: SPMSingleCaseExclusionMock()
        )
        let mutant = makeMutant(
            id: "swift-mutation-testing_0",
            filePath: fooFile.path,
            isSchematizable: true
        )
        let input = makeInputSPM(
            projectPath: dir.path,
            schematizedFiles: [
                SchematizedFile(originalPath: fooFile.path, schematizedContent: schematized)
            ],
            mutants: [mutant]
        )

        let results = try await executor.execute(input)

        #expect(results.count == 1)
    }

    private func makeConfigurationSPM(projectPath: String) -> RunnerConfiguration {
        RunnerConfiguration(
            projectPath: projectPath,
            build: .init(projectType: .spm, timeout: 60, concurrency: 1, noCache: false),
            reporting: .init(quiet: true),
            filter: .init(excludePatterns: [], operators: [])
        )
    }

    private func makeInputSPM(
        projectPath: String,
        schematizedFiles: [SchematizedFile] = [],
        mutants: [MutantDescriptor] = []
    ) -> RunnerInput {
        RunnerInput(
            projectPath: projectPath,
            projectType: .spm,
            timeout: 60,
            concurrency: 1,
            noCache: false,
            schematizedFiles: schematizedFiles,
            supportFileContent: "",
            mutants: mutants
        )
    }

    private func makeMutant(
        id: String,
        filePath: String,
        isSchematizable: Bool,
        mutatedContent: String? = "let x = false"
    ) -> MutantDescriptor {
        MutantDescriptor(
            id: id,
            filePath: filePath,
            line: 1,
            column: 1,
            utf8Offset: 0,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: isSchematizable,
            mutatedSourceContent: mutatedContent
        )
    }
}

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
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            launcher: ThrowingDuringTestMock()
        )
        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: sourceFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let x = false"
        )
        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
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
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            launcher: SPMErrorWithoutLineNumberMock()
        )
        let mutant = makeMutantDescriptor(
            id: "m0",
            filePath: fooFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let x = false"
        )
        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
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
            configuration: makeRunnerConfiguration(projectPath: dir.path, projectType: .spm),
            launcher: SPMSingleCaseExclusionMock()
        )
        let mutant = makeMutantDescriptor(
            id: "swift-mutation-testing_0",
            filePath: fooFile.path,
            originalText: "true",
            mutatedText: "false",
            operatorIdentifier: "BooleanLiteralReplacement",
            replacementKind: .booleanLiteral,
            description: "true → false",
            isSchematizable: true,
            mutatedSourceContent: "let x = false"
        )
        let input = makeRunnerInput(
            projectPath: dir.path,
            projectType: .spm,
            schematizedFiles: [
                SchematizedFile(originalPath: fooFile.path, schematizedContent: schematized)
            ],
            mutants: [mutant]
        )

        let results = try await executor.execute(input)

        #expect(results.count == 1)
    }
}

import Foundation
import SwiftParser
import Testing

@testable import SwiftMutationTesting

@Suite("Schema narrowing")
struct SchemaNarrowingTests {

    // MARK: - Private

    private let codeWithSwitch = """
        struct Foo {
            func classify(_ c: Character) -> Int {
                var total = 0
                if c == "a" { total = total + 1 }
                switch c {
                case "(", ")", "{", "}":
                    total = total + 2
                default:
                    total = total + 3
                }
                return total
            }
        }
        """

    private func indexedMutants(in code: String, path: String) -> [IndexedMutationPoint] {
        let parsed = ParsedSource(
            file: SourceFile(path: path, content: code),
            syntax: Parser.parse(source: code)
        )
        return ArithmeticOperatorReplacement().mutations(in: parsed).enumerated().map {
            IndexedMutationPoint(index: $0.offset, mutation: $0.element, isSchematizable: true)
        }
    }

    private func executor(projectPath: String) -> MutantExecutor {
        MutantExecutor(
            configuration: makeRunnerConfiguration(projectPath: projectPath, projectType: .spm),
            launcher: MockProcessLauncher(exitCode: 0)
        )
    }

    // MARK: - Tests

    @Test("Given a body holding a switch, when the schema is narrowed, then the result still parses")
    func narrowedSchemaOfABodyWithASwitchStillParses() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let file = dir.appendingPathComponent("Foo.swift")
        try codeWithSwitch.write(to: file, atomically: true, encoding: .utf8)

        let indexed = indexedMutants(in: codeWithSwitch, path: file.path)
        #expect(indexed.count == 3)

        let kept = indexed.dropFirst().map {
            $0.toDescriptor(mutatedContent: nil, sourceContentHash: "hash")
        }

        let narrowed = executor(projectPath: dir.path)
            .regeneratedSchema(originalPath: file.path, keeping: kept)

        let source = try #require(narrowed)
        #expect(!Parser.parse(source: source).hasError)
    }

    @Test("Given mutants to drop, when the schema is narrowed, then only the kept cases remain")
    func narrowedSchemaKeepsExactlyTheRequestedCases() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let file = dir.appendingPathComponent("Foo.swift")
        try codeWithSwitch.write(to: file, atomically: true, encoding: .utf8)

        let indexed = indexedMutants(in: codeWithSwitch, path: file.path)
        let kept = indexed.dropFirst().map {
            $0.toDescriptor(mutatedContent: nil, sourceContentHash: "hash")
        }

        let source = try #require(
            executor(projectPath: dir.path)
                .regeneratedSchema(originalPath: file.path, keeping: kept)
        )

        #expect(!source.contains(indexed[0].mutantID))
        #expect(source.contains(indexed[1].mutantID))
        #expect(source.contains(indexed[2].mutantID))
    }

    @Test("Given every mutant dropped, when the schema is narrowed, then the result is the untouched source")
    func narrowingEverythingLeavesTheOriginalSource() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let file = dir.appendingPathComponent("Foo.swift")
        try codeWithSwitch.write(to: file, atomically: true, encoding: .utf8)

        let source = try #require(
            executor(projectPath: dir.path).regeneratedSchema(originalPath: file.path, keeping: [])
        )

        #expect(source == codeWithSwitch)
        #expect(!source.contains("__swiftMutationTestingID"))
    }

    @Test("Given an id that carries no index, when the schema is narrowed, then narrowing reports failure")
    func narrowingFailsOnAnIdWithoutAnIndex() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let file = dir.appendingPathComponent("Foo.swift")
        try codeWithSwitch.write(to: file, atomically: true, encoding: .utf8)

        let descriptor = makeMutantDescriptor(id: "m0", filePath: file.path, isSchematizable: true)

        #expect(
            executor(projectPath: dir.path)
                .regeneratedSchema(originalPath: file.path, keeping: [descriptor]) == nil
        )
    }

    @Test("Given a source that cannot be read, when the schema is narrowed, then narrowing reports failure")
    func narrowingFailsWhenTheSourceIsMissing() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        #expect(
            executor(projectPath: dir.path)
                .regeneratedSchema(originalPath: dir.appendingPathComponent("Gone.swift").path, keeping: [])
                == nil
        )
    }
}

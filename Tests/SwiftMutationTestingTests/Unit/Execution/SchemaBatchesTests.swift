import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("SchemaBatches")
struct SchemaBatchesTests {
    @Test("Given every function within the limit, when split, then the input is the only batch")
    func functionsWithinTheLimitMakeOneBatch() throws {
        let fixture = try Fixture(functions: [2, 1])
        defer { fixture.cleanUp() }

        let batches = SchemaBatches(limit: 2).split(fixture.input)

        #expect(batches.count == 1)
        #expect(batches[0].mutants.map(\.id) == fixture.input.mutants.map(\.id))
        #expect(
            batches[0].schematizedFiles.map(\.schematizedContent)
                == fixture.input.schematizedFiles.map(\.schematizedContent)
        )
    }

    @Test("Given a function over the limit, when split, then each batch holds at most the limit of its mutants")
    func aFunctionOverTheLimitIsSpreadOverBatches() throws {
        let fixture = try Fixture(functions: [5])
        defer { fixture.cleanUp() }

        let batches = SchemaBatches(limit: 2).split(fixture.input)

        #expect(batches.map { $0.mutants.map(\.id) } == [[0, 1], [2, 3], [4]].map(fixture.ids))
        for batch in batches {
            let schema = try #require(batch.schematizedFiles.first?.schematizedContent)
            for mutant in fixture.input.mutants {
                #expect(schema.contains("case \"\(mutant.id)\":") == batch.mutants.contains { $0.id == mutant.id })
            }
        }
    }

    @Test("Given two functions, when one is over the limit, then the other stays whole in the first batch")
    func theLimitAppliesToEachFunctionOnItsOwn() throws {
        let fixture = try Fixture(functions: [3, 2])
        defer { fixture.cleanUp() }

        let batches = SchemaBatches(limit: 2).split(fixture.input)

        #expect(batches.map { $0.mutants.map(\.id) } == [[0, 1, 3, 4], [2]].map(fixture.ids))
    }

    @Test("Given mutants outside the split file, when split, then they all run in the first batch")
    func otherMutantsStayInTheFirstBatch() throws {
        let fixture = try Fixture(functions: [3])
        defer { fixture.cleanUp() }
        let other = SchematizedFile(originalPath: "/tmp/Other.swift", schematizedContent: "other schema")
        let input = makeRunnerInput(
            schematizedFiles: fixture.input.schematizedFiles + [other],
            mutants: fixture.input.mutants + [
                makeMutantDescriptor(id: "other", filePath: other.originalPath, isSchematizable: true),
                makeMutantDescriptor(id: "incompatible", filePath: fixture.file.path),
            ]
        )

        let batches = SchemaBatches(limit: 2).split(input)

        #expect(batches.count == 2)
        #expect(batches[0].mutants.map(\.id) == fixture.ids([0, 1]) + ["other", "incompatible"])
        #expect(batches[0].schematizedFiles.map(\.originalPath) == [fixture.file.path, other.originalPath])
        #expect(batches[1].mutants.map(\.id) == fixture.ids([2]))
        #expect(batches[1].schematizedFiles.map(\.originalPath) == [fixture.file.path])
    }

    // MARK: - Private

    private struct Fixture {
        let directory: URL
        let file: URL
        let input: RunnerInput

        init(functions mutantCounts: [Int]) throws {
            directory = try FileHelpers.makeTemporaryDirectory()
            file = directory.appendingPathComponent("Foo.swift")

            var source = ""
            for (function, count) in mutantCounts.enumerated() {
                let statements = (0 ..< count).map { "let v\($0) = true" }.joined(separator: "; ")
                source += "func f\(function)() { \(statements) }\n"
            }
            try source.write(to: file, atomically: true, encoding: .utf8)

            var mutants: [MutantDescriptor] = []
            var searchStart = source.startIndex
            while let range = source.range(of: "true", range: searchStart ..< source.endIndex) {
                mutants.append(
                    makeMutantDescriptor(
                        id: MutantID.make(index: mutants.count), filePath: file.path,
                        utf8Offset: source.utf8.distance(from: source.startIndex, to: range.lowerBound),
                        originalText: "true", mutatedText: "false", replacementKind: .booleanLiteral,
                        isSchematizable: true
                    )
                )
                searchStart = range.upperBound
            }

            let schema = try #require(SchemaNarrower.regeneratedSchema(originalPath: file.path, keeping: mutants))
            input = makeRunnerInput(
                projectPath: directory.path,
                schematizedFiles: [SchematizedFile(originalPath: file.path, schematizedContent: schema)],
                mutants: mutants
            )
        }

        func ids(_ indices: [Int]) -> [String] {
            indices.map { MutantID.make(index: $0) }
        }

        func cleanUp() {
            FileHelpers.cleanup(directory)
        }
    }
}

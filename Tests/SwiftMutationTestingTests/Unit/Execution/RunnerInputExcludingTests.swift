import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("RunnerInput excluding")
struct RunnerInputExcludingTests {

    @Test("Given no ids, when excluding, then the input is unchanged")
    func noIDsLeaveTheInputAsItIs() {
        let input = makeRunnerInput(
            schematizedFiles: [SchematizedFile(originalPath: "/tmp/Foo.swift", schematizedContent: "schema")],
            mutants: [makeMutantDescriptor(id: "a", filePath: "/tmp/Foo.swift", isSchematizable: true)]
        )

        let result = input.excluding([])

        #expect(result.mutants.map(\.id) == ["a"])
        #expect(result.schematizedFiles.map(\.schematizedContent) == input.schematizedFiles.map(\.schematizedContent))
    }

    @Test("Given a file whose mutants are all excluded, when excluding, then the file and its mutants are left out")
    func aFileWithNothingLeftIsDropped() {
        let input = makeRunnerInput(
            schematizedFiles: [
                SchematizedFile(originalPath: "/tmp/Foo.swift", schematizedContent: "foo schema"),
                SchematizedFile(originalPath: "/tmp/Bar.swift", schematizedContent: "bar schema"),
            ],
            mutants: [
                makeMutantDescriptor(id: "a", filePath: "/tmp/Foo.swift", isSchematizable: true),
                makeMutantDescriptor(id: "b", filePath: "/tmp/Bar.swift", isSchematizable: true),
                makeMutantDescriptor(id: "c", filePath: "/tmp/Baz.swift"),
            ]
        )

        let result = input.excluding(["b"])

        #expect(result.mutants.map(\.id) == ["a", "c"])
        #expect(result.schematizedFiles.map(\.originalPath) == ["/tmp/Foo.swift"])
        #expect(result.schematizedFiles.map(\.schematizedContent) == [input.schematizedFiles[0].schematizedContent])
    }

    @Test("Given a file that keeps some mutants, when excluding, then its schema is made again without the others")
    func aFileWithMutantsLeftGetsANarrowerSchema() throws {
        let directory = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(directory) }

        let file = directory.appendingPathComponent("Foo.swift")
        try "func f() { let x = true; let y = true }".write(to: file, atomically: true, encoding: .utf8)
        let mutants = [19, 33].enumerated().map { index, offset in
            makeMutantDescriptor(
                id: "swift-mutation-testing_\(index)", filePath: file.path, utf8Offset: offset,
                originalText: "true", mutatedText: "false", replacementKind: .booleanLiteral, isSchematizable: true
            )
        }
        let full = try #require(SchemaNarrower.regeneratedSchema(originalPath: file.path, keeping: mutants))
        let input = makeRunnerInput(
            schematizedFiles: [SchematizedFile(originalPath: file.path, schematizedContent: full)],
            mutants: mutants
        )

        let result = input.excluding(["swift-mutation-testing_1"])
        let schema = try #require(result.schematizedFiles.first?.schematizedContent)

        #expect(result.mutants.map(\.id) == ["swift-mutation-testing_0"])
        #expect(schema.contains("case \"swift-mutation-testing_0\":"))
        #expect(!schema.contains("case \"swift-mutation-testing_1\":"))
    }

    @Test("Given a schema that cannot be made again, when excluding, then the file keeps the schema it had")
    func aSchemaThatCannotBeRegeneratedIsKept() {
        let input = makeRunnerInput(
            schematizedFiles: [SchematizedFile(originalPath: "/nonexistent/Foo.swift", schematizedContent: "schema")],
            mutants: [
                makeMutantDescriptor(
                    id: "swift-mutation-testing_0", filePath: "/nonexistent/Foo.swift", isSchematizable: true),
                makeMutantDescriptor(
                    id: "swift-mutation-testing_1", filePath: "/nonexistent/Foo.swift", isSchematizable: true),
            ]
        )

        let result = input.excluding(["swift-mutation-testing_1"])

        #expect(result.mutants.map(\.id) == ["swift-mutation-testing_0"])
        #expect(result.schematizedFiles.map(\.schematizedContent) == input.schematizedFiles.map(\.schematizedContent))
    }
}

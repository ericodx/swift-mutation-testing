import Testing

@testable import SwiftMutationTesting

@Suite("SchematizationStage")
struct SchematizationStageTests {
    private let stage = SchematizationStage()

    @Test("Given schematizable mutation, when run, then produces one schematized file")
    func schematizableMutationProducesSchematizedFile() {
        let source = makeParsedSource("func f() { let x = true }", path: "a.swift")
        let indexed = makeIndexed(source: source, operators: [BooleanLiteralReplacement()])
        let (files, _) = stage.run(indexed: indexed, sources: [source])
        #expect(files.count == 1)
        #expect(files[0].originalPath == "a.swift")
    }

    @Test("Given schematizable mutation, when run, then descriptor has correct flags")
    func schematizableMutationDescriptorHasCorrectFlags() {
        let source = makeParsedSource("func f() { let x = true }", path: "a.swift")
        let indexed = makeIndexed(source: source, operators: [BooleanLiteralReplacement()])
        let (_, descriptors) = stage.run(indexed: indexed, sources: [source])
        #expect(descriptors[0].isSchematizable)
        #expect(descriptors[0].mutatedSourceContent == nil)
    }

    @Test("Given schematized content, when checked, then does not contain var __swiftMutationTestingID declaration")
    func schematizedContentDoesNotDeclareIDVariable() {
        let source = makeParsedSource("func f() { let x = true }", path: "a.swift")
        let indexed = makeIndexed(source: source, operators: [BooleanLiteralReplacement()])
        let (files, _) = stage.run(indexed: indexed, sources: [source])
        #expect(!files[0].schematizedContent.contains("var __swiftMutationTestingID"))
    }

    @Test("Given any input, when checked, then supportFileContent declares __swiftMutationTestingID")
    func supportFileContentDeclaresIDVariable() {
        #expect(SchematizationStage.supportFileContent.contains("__swiftMutationTestingID"))
        #expect(SchematizationStage.supportFileContent.contains("__SWIFT_MUTATION_TESTING_ACTIVE"))
    }

    @Test("Given mutation point for unknown file path, when run, then skips it and returns empty")
    func mutationForUnknownFilePathIsSkipped() {
        let source = makeParsedSource("func f() { let x = true }", path: "a.swift")
        let indexed = makeIndexed(source: source, operators: [BooleanLiteralReplacement()])
        let (files, descriptors) = stage.run(indexed: indexed, sources: [])
        #expect(files.isEmpty)
        #expect(descriptors.isEmpty)
    }

    @Test("Given empty indexed list, when run, then returns empty")
    func emptyIndexedListReturnsEmpty() {
        let source = makeParsedSource("func f() { let x = 1 }", path: "a.swift")
        let (files, descriptors) = stage.run(indexed: [], sources: [source])
        #expect(files.isEmpty)
        #expect(descriptors.isEmpty)
    }

    private func makeIndexed(source: ParsedSource, operators: [any MutationOperator]) -> [IndexedMutationPoint] {
        let points = operators.flatMap { $0.mutations(in: source) }
        return MutantIndexingStage().run(mutationPoints: points, sources: [source])
    }
}

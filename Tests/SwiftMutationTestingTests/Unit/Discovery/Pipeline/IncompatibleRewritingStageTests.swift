import Testing

@testable import SwiftMutationTesting

@Suite("IncompatibleRewritingStage")
struct IncompatibleRewritingStageTests {
    private let stage = IncompatibleRewritingStage()

    @Test("Given mutation at file scope, when run, then descriptor is marked as incompatible")
    func fileScopeMutationIsIncompatible() {
        let source = makeParsedSource("let x = true", path: "a.swift")
        let indexed = makeIndexedMutationPoints(source: source, operators: [BooleanLiteralReplacement()])
        let descriptors = stage.run(indexed: indexed, sources: [source])
        #expect(!descriptors.isEmpty)
        #expect(descriptors.allSatisfy { !$0.isSchematizable })
        #expect(descriptors.allSatisfy { $0.mutatedSourceContent != nil })
    }

    @Test("Given incompatible mutation, when run, then mutatedSourceContent contains the mutation applied")
    func incompatibleMutationContentHasMutationApplied() throws {
        let source = makeParsedSource("let x = true", path: "a.swift")
        let indexed = makeIndexedMutationPoints(source: source, operators: [BooleanLiteralReplacement()])
        let descriptors = stage.run(indexed: indexed, sources: [source])
        let content = try #require(descriptors.first?.mutatedSourceContent)
        #expect(content.contains("false"))
    }

    @Test("Given schematizable mutation, when run, then returns no descriptors")
    func schematizableMutationProducesNoDescriptors() {
        let source = makeParsedSource("func f() { let x = true }", path: "a.swift")
        let indexed = makeIndexedMutationPoints(source: source, operators: [BooleanLiteralReplacement()])
        let descriptors = stage.run(indexed: indexed, sources: [source])
        #expect(descriptors.isEmpty)
    }

    @Test("Given mutation point for unknown file path, when run, then skips it")
    func mutationForUnknownFilePathIsSkipped() {
        let source = makeParsedSource("let x = true", path: "a.swift")
        let indexed = makeIndexedMutationPoints(source: source, operators: [BooleanLiteralReplacement()])
        let descriptors = stage.run(indexed: indexed, sources: [])
        #expect(descriptors.isEmpty)
    }

    @Test("Given empty indexed list, when run, then returns empty")
    func emptyIndexedListReturnsEmpty() {
        let source = makeParsedSource("let x = true", path: "a.swift")
        let descriptors = stage.run(indexed: [], sources: [source])
        #expect(descriptors.isEmpty)
    }

}

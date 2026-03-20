import Testing

@testable import SwiftMutationTesting

@Suite("SchematizationStage")
struct SchematizationStageTests {
    private let stage = SchematizationStage()

    @Test("Given mutation in function body, when run, then produces one schematized file")
    func schematizableMutationProducesSchematizedFile() {
        let source = makeParsedSource("func f() { let x = true }", path: "a.swift")
        let mutations = BooleanLiteralReplacement().mutations(in: source)
        let result = stage.run(mutationPoints: mutations, sources: [source])
        #expect(result.schematizedFiles.count == 1)
        #expect(result.schematizedFiles[0].originalPath == "a.swift")
    }

    @Test("Given schematizable mutation, when run, then descriptor has correct schematizability flags")
    func schematizableMutationDescriptorHasCorrectFlags() {
        let source = makeParsedSource("func f() { let x = true }", path: "a.swift")
        let mutations = BooleanLiteralReplacement().mutations(in: source)
        let result = stage.run(mutationPoints: mutations, sources: [source])
        #expect(result.descriptors[0].isSchematizable == true)
        #expect(result.descriptors[0].mutatedSourceContent == nil)
    }

    @Test("Given mutation at file scope, when run, then descriptor is marked as incompatible")
    func fileScopeMutationIsIncompatible() {
        let source = makeParsedSource("let x = true", path: "a.swift")
        let mutations = BooleanLiteralReplacement().mutations(in: source)
        let result = stage.run(mutationPoints: mutations, sources: [source])
        #expect(result.descriptors[0].isSchematizable == false)
        #expect(result.descriptors[0].mutatedSourceContent != nil)
        #expect(result.schematizedFiles.isEmpty)
    }

    @Test("Given incompatible mutation, when run, then mutatedSourceContent has mutation applied")
    func incompatibleMutationContentHasMutationApplied() {
        let source = makeParsedSource("let x = true", path: "a.swift")
        let mutations = BooleanLiteralReplacement().mutations(in: source)
        let result = stage.run(mutationPoints: mutations, sources: [source])
        #expect(result.descriptors[0].mutatedSourceContent?.contains("false") == true)
    }

    @Test("Given multiple mutations across files, when run, then descriptors are sorted by global index")
    func descriptorsAreSortedByIndex() {
        let sourceA = makeParsedSource("func f() { let x = true }", path: "a.swift")
        let sourceB = makeParsedSource("func g() { let y = false }", path: "b.swift")
        let mutationsA = BooleanLiteralReplacement().mutations(in: sourceA)
        let mutationsB = BooleanLiteralReplacement().mutations(in: sourceB)
        let result = stage.run(
            mutationPoints: mutationsA + mutationsB,
            sources: [sourceA, sourceB]
        )
        #expect(result.descriptors.count == 2)
        let ids = result.descriptors.map { $0.id }
        #expect(ids[0] == "swift-mutation-testing_0")
        #expect(ids[1] == "swift-mutation-testing_1")
    }

    @Test("Given any input, when run, then supportFileContent declares __swiftMutationTestingID")
    func supportFileContentDeclaresIDVariable() {
        let source = makeParsedSource("func f() { let x = true }", path: "a.swift")
        let mutations = BooleanLiteralReplacement().mutations(in: source)
        let result = stage.run(mutationPoints: mutations, sources: [source])
        #expect(result.supportFileContent.contains("__swiftMutationTestingID"))
        #expect(result.supportFileContent.contains("__SWIFT_MUTATION_TESTING_ACTIVE"))
    }

    @Test("Given schematized content, when checked, then does not contain var __swiftMutationTestingID declaration")
    func schematizedContentDoesNotDeclareIDVariable() {
        let source = makeParsedSource("func f() { let x = true }", path: "a.swift")
        let mutations = BooleanLiteralReplacement().mutations(in: source)
        let result = stage.run(mutationPoints: mutations, sources: [source])
        let schematizedContent = result.schematizedFiles[0].schematizedContent
        #expect(!schematizedContent.contains("var __swiftMutationTestingID"))
    }

    @Test("Given mutation, when run, then descriptor ID uses correct format")
    func descriptorIDUsesCorrectFormat() {
        let source = makeParsedSource("func f() { let x = true }", path: "a.swift")
        let mutations = BooleanLiteralReplacement().mutations(in: source)
        let result = stage.run(mutationPoints: mutations, sources: [source])
        #expect(result.descriptors[0].id == "swift-mutation-testing_0")
    }

    @Test("Given empty mutation points, when run, then returns empty result")
    func emptyMutationPointsReturnsEmptyResult() {
        let source = makeParsedSource("func f() { let x = 1 }", path: "a.swift")
        let result = stage.run(mutationPoints: [], sources: [source])
        #expect(result.schematizedFiles.isEmpty)
        #expect(result.descriptors.isEmpty)
    }
}

import Testing

@testable import SwiftMutationTesting

@Suite("MutantIndexingStage")
struct MutantIndexingStageTests {
    private let stage = MutantIndexingStage()

    @Test("Given empty mutation points, when run, then returns empty")
    func emptyMutationPointsReturnsEmpty() {
        let source = makeParsedSource("func f() { let x = 1 }", path: "a.swift")
        let result = stage.run(mutationPoints: [], sources: [source])
        #expect(result.isEmpty)
    }

    @Test("Given mutation in function body, when run, then isSchematizable is true")
    func mutationInFunctionBodyIsSchematizable() {
        let source = makeParsedSource("func f() { let x = true }", path: "a.swift")
        let points = BooleanLiteralReplacement().mutations(in: source)
        let result = stage.run(mutationPoints: points, sources: [source])
        #expect(result.allSatisfy { $0.isSchematizable })
    }

    @Test("Given mutation at file scope, when run, then isSchematizable is false")
    func mutationAtFileScopeIsNotSchematizable() {
        let source = makeParsedSource("let x = true", path: "a.swift")
        let points = BooleanLiteralReplacement().mutations(in: source)
        let result = stage.run(mutationPoints: points, sources: [source])
        #expect(result.allSatisfy { !$0.isSchematizable })
    }

    @Test("Given mutation points, when run, then indices are zero-based and sequential")
    func indicesAreZeroBasedAndSequential() {
        let source = makeParsedSource("func f() { let x = true }", path: "a.swift")
        let points = BooleanLiteralReplacement().mutations(in: source)
        let result = stage.run(mutationPoints: points, sources: [source])
        for (pos, entry) in result.enumerated() {
            #expect(entry.index == pos)
        }
    }

    @Test("Given mutations across two files, when run, then sorted by file path then offset")
    func sortsByFilePathThenOffset() {
        let sourceA = makeParsedSource("func f() { let x = true }", path: "b.swift")
        let sourceB = makeParsedSource("func g() { let y = false }", path: "a.swift")
        let pointsA = BooleanLiteralReplacement().mutations(in: sourceA)
        let pointsB = BooleanLiteralReplacement().mutations(in: sourceB)
        let result = stage.run(mutationPoints: pointsA + pointsB, sources: [sourceA, sourceB])

        #expect(result.count == 2)
        #expect(result[0].mutation.filePath == "a.swift")
        #expect(result[1].mutation.filePath == "b.swift")
    }

    @Test("Given mutation with filePath not in sources, when run, then isSchematizable defaults to false")
    func missingSourceDefaultsToNotSchematizable() {
        let source = makeParsedSource("func f() { let x = true }", path: "a.swift")
        let points = BooleanLiteralReplacement().mutations(in: source)
        let result = stage.run(mutationPoints: points, sources: [])
        #expect(result.allSatisfy { !$0.isSchematizable })
    }
}

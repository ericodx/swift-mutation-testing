import Testing

@testable import SwiftMutationTesting

@Suite("MutantDiscoveryStage")
struct MutantDiscoveryStageTests {
    @Test("Given source with mutations, when run, then collects mutations from all operators")
    func collectsMutationsFromOperators() async {
        let stage = MutantDiscoveryStage(operators: [BooleanLiteralReplacement()])
        let source = makeParsedSource("func f() { let a = true; let b = false }", path: "a.swift")
        let result = await stage.run(sources: [source])
        #expect(result.count == 2)
    }

    @Test("Given multiple operators, when run, then collects mutations from each")
    func collectsFromMultipleOperators() async {
        let stage = MutantDiscoveryStage(operators: [BooleanLiteralReplacement(), RemoveSideEffects()])
        let source = makeParsedSource("func f() { let x = true; notify() }", path: "a.swift")
        let result = await stage.run(sources: [source])
        #expect(result.count == 2)
    }

    @Test("Given source with suppression annotation, when run, then filters suppressed mutations")
    func filtersSuppressedMutations() async {
        let stage = MutantDiscoveryStage(operators: [BooleanLiteralReplacement()])
        let code = """
            @SwiftMutationTestingDisabled func suppressed() { let x = true }
            func active() { let y = false }
            """
        let source = makeParsedSource(code, path: "a.swift")
        let result = await stage.run(sources: [source])
        #expect(result.count == 1)
        #expect(result[0].originalText == "false")
    }

    @Test("Given multiple sources, when run, then result is sorted by filePath then utf8Offset")
    func resultIsSortedByFilePathThenOffset() async {
        let stage = MutantDiscoveryStage(operators: [BooleanLiteralReplacement()])
        let sourceA = makeParsedSource("func f() { let x = true }", path: "z.swift")
        let sourceB = makeParsedSource("func f() { let x = true }", path: "a.swift")
        let result = await stage.run(sources: [sourceA, sourceB])
        #expect(result.count == 2)
        #expect(result[0].filePath == "a.swift")
        #expect(result[1].filePath == "z.swift")
    }

    @Test("Given source with multiple mutations in same file, when run, then sorted by utf8Offset")
    func resultIsSortedByOffsetWithinFile() async {
        let stage = MutantDiscoveryStage(operators: [BooleanLiteralReplacement()])
        let source = makeParsedSource("func f() { let a = true; let b = false }", path: "a.swift")
        let result = await stage.run(sources: [source])
        #expect(result.count == 2)
        #expect(result[0].utf8Offset < result[1].utf8Offset)
    }

    @Test("Given empty sources, when run, then returns empty array")
    func emptySourcesReturnsEmpty() async {
        let stage = MutantDiscoveryStage(operators: [BooleanLiteralReplacement()])
        let result = await stage.run(sources: [])
        #expect(result.isEmpty)
    }

    @Test("Given source with no mutations, when run, then returns empty array")
    func noMutationsReturnsEmpty() async {
        let stage = MutantDiscoveryStage(operators: [BooleanLiteralReplacement()])
        let source = makeParsedSource("func f() { let x = 1 }", path: "a.swift")
        let result = await stage.run(sources: [source])
        #expect(result.isEmpty)
    }
}

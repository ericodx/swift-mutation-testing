import Testing

@testable import SwiftMutationTesting

@Suite("BooleanLiteralReplacement")
struct BooleanLiteralReplacementTests {
    private let op = BooleanLiteralReplacement()

    @Test("Given no boolean literals, when visited, then returns no mutations")
    func noBooleanLiterals() {
        let source = makeParsedSource("func f() { let x = 1 }")
        #expect(op.mutations(in: source).isEmpty)
    }

    @Test("Given true literal, when visited, then produces mutation to false")
    func trueMutatedToFalse() {
        let source = makeParsedSource("func f() { let x = true }")
        let result = op.mutations(in: source)
        #expect(result.count == 1)
        #expect(result[0].originalText == "true")
        #expect(result[0].mutatedText == "false")
        #expect(result[0].replacement == .booleanLiteral)
    }

    @Test("Given false literal, when visited, then produces mutation to true")
    func falseMutatedToTrue() {
        let source = makeParsedSource("func f() { let x = false }")
        let result = op.mutations(in: source)
        #expect(result.count == 1)
        #expect(result[0].originalText == "false")
        #expect(result[0].mutatedText == "true")
    }

    @Test("Given multiple boolean literals, when visited, then produces one mutation per literal")
    func multipleLiteralsProduceSeparateMutations() {
        let source = makeParsedSource("func f() { let a = true; let b = false }")
        let result = op.mutations(in: source)
        #expect(result.count == 2)
    }

    @Test("Given boolean literal, when visited, then mutation carries correct operator identifier")
    func mutationCarriesCorrectOperatorIdentifier() {
        let source = makeParsedSource("func f() { let x = true }")
        let result = op.mutations(in: source)
        #expect(result[0].operatorIdentifier == "BooleanLiteralReplacement")
    }
}

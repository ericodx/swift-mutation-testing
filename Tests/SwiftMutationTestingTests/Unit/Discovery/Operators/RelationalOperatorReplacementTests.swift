import Testing

@testable import SwiftMutationTesting

@Suite("RelationalOperatorReplacement")
struct RelationalOperatorReplacementTests {
    private let op = RelationalOperatorReplacement()

    @Test("Given no relational operators, when visited, then returns no mutations")
    func noRelationalOperators() {
        let source = makeParsedSource("func f() { let x = 1 + 2 }")
        #expect(op.mutations(in: source).isEmpty)
    }

    @Test("Given == operator, when visited, then produces one mutation to !=")
    func equalityProducesOneReplacement() {
        let source = makeParsedSource("func f() { if a == b {} }")
        let result = op.mutations(in: source)
        #expect(result.count == 1)
        #expect(result[0].originalText == "==")
        #expect(result[0].mutatedText == "!=")
        #expect(result[0].replacement == .binaryOperator)
    }

    @Test("Given != operator, when visited, then produces one mutation to ==")
    func inequalityProducesOneReplacement() {
        let source = makeParsedSource("func f() { if a != b {} }")
        let result = op.mutations(in: source)
        #expect(result.count == 1)
        #expect(result[0].originalText == "!=")
        #expect(result[0].mutatedText == "==")
    }

    @Test("Given > operator, when visited, then produces two mutations")
    func greaterThanProducesTwoReplacements() {
        let source = makeParsedSource("func f() { if a > b {} }")
        let result = op.mutations(in: source)
        #expect(result.count == 2)
        let mutated = Set(result.map(\.mutatedText))
        #expect(mutated == [">=", "<"])
    }

    @Test("Given >= operator, when visited, then produces two mutations")
    func greaterThanOrEqualProducesTwoReplacements() {
        let source = makeParsedSource("func f() { if a >= b {} }")
        let result = op.mutations(in: source)
        #expect(result.count == 2)
        let mutated = Set(result.map(\.mutatedText))
        #expect(mutated == [">", "<="])
    }

    @Test("Given < operator, when visited, then produces two mutations")
    func lessThanProducesTwoReplacements() {
        let source = makeParsedSource("func f() { if a < b {} }")
        let result = op.mutations(in: source)
        #expect(result.count == 2)
        let mutated = Set(result.map(\.mutatedText))
        #expect(mutated == ["<=", ">"])
    }

    @Test("Given multiple relational operators, when visited, then produces mutations for each")
    func multipleOperatorsProduceMutationsForEach() {
        let source = makeParsedSource("func f() { if a == b && c != d {} }")
        let result = op.mutations(in: source)
        #expect(result.count == 2)
    }

    @Test("Given relational operator, when visited, then mutation carries correct operator identifier")
    func mutationCarriesCorrectOperatorIdentifier() {
        let source = makeParsedSource("func f() { if a == b {} }")
        let result = op.mutations(in: source)
        #expect(result[0].operatorIdentifier == "RelationalOperatorReplacement")
    }
}

import Testing

@testable import SwiftMutationTesting

@Suite("LogicalOperatorReplacement")
struct LogicalOperatorReplacementTests {
    private let op = LogicalOperatorReplacement()

    @Test("Given no logical operators, when visited, then returns no mutations")
    func noLogicalOperators() {
        let source = makeParsedSource("func f() { if a == b {} }")
        #expect(op.mutations(in: source).isEmpty)
    }

    @Test("Given && operator, when visited, then produces mutation to ||")
    func andMutatedToOr() {
        let source = makeParsedSource("func f() { if a && b {} }")
        let result = op.mutations(in: source)
        #expect(result.count == 1)
        #expect(result[0].originalText == "&&")
        #expect(result[0].mutatedText == "||")
        #expect(result[0].replacement == .binaryOperator)
    }

    @Test("Given || operator, when visited, then produces mutation to &&")
    func orMutatedToAnd() {
        let source = makeParsedSource("func f() { if a || b {} }")
        let result = op.mutations(in: source)
        #expect(result.count == 1)
        #expect(result[0].originalText == "||")
        #expect(result[0].mutatedText == "&&")
    }

    @Test("Given mixed logical operators, when visited, then produces one mutation per operator")
    func mixedOperatorsProduceSeparateMutations() {
        let source = makeParsedSource("func f() { if a && b || c {} }")
        let result = op.mutations(in: source)
        #expect(result.count == 2)
    }

    @Test("Given logical operator, when visited, then mutation carries correct operator identifier")
    func mutationCarriesCorrectOperatorIdentifier() {
        let source = makeParsedSource("func f() { if a && b {} }")
        let result = op.mutations(in: source)
        #expect(result[0].operatorIdentifier == "LogicalOperatorReplacement")
    }
}

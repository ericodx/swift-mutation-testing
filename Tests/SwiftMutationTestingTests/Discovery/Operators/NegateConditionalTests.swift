import Testing

@testable import SwiftMutationTesting

@Suite("NegateConditional")
struct NegateConditionalTests {
    private let op = NegateConditional()

    @Test("Given no conditional, when visited, then returns no mutations")
    func noConditional() {
        let source = makeParsedSource("func f() { let x = 1 }")
        #expect(op.mutations(in: source).isEmpty)
    }

    @Test("Given if condition, when visited, then produces one mutation wrapping with negation")
    func ifConditionProducesNegation() {
        let source = makeParsedSource("func f() { if isEnabled {} }")
        let result = op.mutations(in: source)
        #expect(result.count == 1)
        #expect(result[0].originalText == "isEnabled")
        #expect(result[0].mutatedText == "!(isEnabled)")
        #expect(result[0].replacement == .wrapWithNegation)
    }

    @Test("Given while condition, when visited, then produces one mutation")
    func whileConditionProducesNegation() {
        let source = makeParsedSource("func f() { while isRunning {} }")
        let result = op.mutations(in: source)
        #expect(result.count == 1)
        #expect(result[0].originalText == "isRunning")
    }

    @Test("Given guard condition, when visited, then produces one mutation")
    func guardConditionProducesNegation() {
        let source = makeParsedSource("func f() { guard isValid else { return } }")
        let result = op.mutations(in: source)
        #expect(result.count == 1)
        #expect(result[0].originalText == "isValid")
    }

    @Test("Given multiple conditions, when visited, then produces one mutation per condition")
    func multipleConditionsProduceSeparateMutations() {
        let source = makeParsedSource("func f() { if a && b {} }")
        let result = op.mutations(in: source)
        #expect(result.count == 1)
        #expect(result[0].originalText == "a && b")
    }

    @Test("Given conditional, when visited, then mutation carries correct operator identifier")
    func mutationCarriesCorrectOperatorIdentifier() {
        let source = makeParsedSource("func f() { if x {} }")
        let result = op.mutations(in: source)
        #expect(result[0].operatorIdentifier == "NegateConditional")
    }

    @Test("Given let binding condition, when visited, then produces no mutation")
    func letBindingConditionProducesNoMutation() {
        let source = makeParsedSource("func f() { if let x = optional { } }")
        let result = op.mutations(in: source)
        #expect(result.isEmpty)
    }
}

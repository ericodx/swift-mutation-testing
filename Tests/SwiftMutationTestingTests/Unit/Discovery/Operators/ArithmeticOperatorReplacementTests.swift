import Testing

@testable import SwiftMutationTesting

@Suite("ArithmeticOperatorReplacement")
struct ArithmeticOperatorReplacementTests {
    private let op = ArithmeticOperatorReplacement()

    @Test("Given string literal concatenation, when visited, then returns no mutations")
    func stringLiteralConcatenationProducesNoMutations() {
        let source = makeParsedSource(#"func f() { let x = "a" + "b" }"#)
        #expect(op.mutations(in: source).isEmpty)
    }

    @Test("Given string interpolation on left side, when visited, then returns no mutations")
    func stringInterpolationLeftProducesNoMutations() {
        let source = makeParsedSource(#"func f(x: String) { let r = "\(x)" + y }"#)
        #expect(op.mutations(in: source).isEmpty)
    }

    @Test("Given integer addition, when visited, then produces one mutation to subtraction")
    func integerAdditionProducesOneMutation() {
        let source = makeParsedSource("func f() { let x = count + 1 }")
        let result = op.mutations(in: source)
        #expect(result.count == 1)
        #expect(result[0].originalText == "+")
        #expect(result[0].mutatedText == "-")
        #expect(result[0].replacement == .binaryOperator)
    }

    @Test("Given floating point multiplication, when visited, then produces one mutation to division")
    func floatMultiplicationProducesOneMutation() {
        let source = makeParsedSource("func f() { let x = x * 2.0 }")
        let result = op.mutations(in: source)
        #expect(result.count == 1)
        #expect(result[0].originalText == "*")
        #expect(result[0].mutatedText == "/")
    }

    @Test("Given subtraction, when visited, then produces mutation to addition")
    func subtractionMutatedToAddition() {
        let source = makeParsedSource("func f() { let x = a - b }")
        let result = op.mutations(in: source)
        #expect(result.count == 1)
        #expect(result[0].originalText == "-")
        #expect(result[0].mutatedText == "+")
    }

    @Test("Given division, when visited, then produces mutation to multiplication")
    func divisionMutatedToMultiplication() {
        let source = makeParsedSource("func f() { let x = a / b }")
        let result = op.mutations(in: source)
        #expect(result.count == 1)
        #expect(result[0].mutatedText == "*")
    }

    @Test("Given modulo, when visited, then produces mutation to multiplication")
    func moduloMutatedToMultiplication() {
        let source = makeParsedSource("func f() { let x = a % b }")
        let result = op.mutations(in: source)
        #expect(result.count == 1)
        #expect(result[0].mutatedText == "*")
    }

    @Test("Given string literal on right side of addition, when visited, then returns no mutations")
    func stringLiteralOnRightProducesNoMutations() {
        let source = makeParsedSource(#"func f(n: String) { let x = n + "suffix" }"#)
        #expect(op.mutations(in: source).isEmpty)
    }

    @Test("Given no arithmetic operators, when visited, then returns no mutations")
    func noArithmeticOperators() {
        let source = makeParsedSource("func f() { if a == b {} }")
        #expect(op.mutations(in: source).isEmpty)
    }

    @Test("Given arithmetic operator, when visited, then mutation carries correct operator identifier")
    func mutationCarriesCorrectOperatorIdentifier() {
        let source = makeParsedSource("func f() { let x = a + b }")
        let result = op.mutations(in: source)
        #expect(result[0].operatorIdentifier == "ArithmeticOperatorReplacement")
    }
}

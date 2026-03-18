import Testing

@testable import SwiftMutationTesting

@Suite("SwapTernary")
struct SwapTernaryTests {
    private let op = SwapTernary()

    @Test("Given no ternary, when visited, then returns no mutations")
    func noTernary() {
        let source = makeParsedSource("func f() { let x = 1 }")
        #expect(op.mutations(in: source).isEmpty)
    }

    @Test("Given ternary expression, when visited, then produces one mutation")
    func ternaryProducesOneMutation() {
        let source = makeParsedSource("func f() { let x = a ? b : c }")
        let result = op.mutations(in: source)
        #expect(result.count == 1)
        #expect(result[0].replacement == .swapTernary)
        #expect(result[0].operatorIdentifier == "SwapTernary")
    }

    @Test("Given ternary expression, when visited, then mutated text swaps branches")
    func mutatedTextHasSwappedBranches() {
        let source = makeParsedSource("func f() { let x = flag ? yes : no }")
        let result = op.mutations(in: source)
        #expect(result.count == 1)
        #expect(result[0].originalText == "flag")
        #expect(result[0].mutatedText == "flag ? no : yes")
    }

    @Test("Given nested ternary, when visited, then produces one mutation per ternary")
    func nestedTernaryProducesOneMutationPerLevel() {
        let source = makeParsedSource("func f() { let x = a ? (b ? c : d) : e }")
        let result = op.mutations(in: source)
        #expect(result.count == 2)
    }

    @Test("Given ternary, when visited, then mutation description is swap ternary branches")
    func mutationDescriptionIsSwapTernaryBranches() {
        let source = makeParsedSource("func f() { let x = a ? b : c }")
        let result = op.mutations(in: source)
        #expect(result[0].description == "swap ternary branches")
    }
}

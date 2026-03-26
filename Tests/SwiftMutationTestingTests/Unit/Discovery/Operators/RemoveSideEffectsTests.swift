import Testing

@testable import SwiftMutationTesting

@Suite("RemoveSideEffects")
struct RemoveSideEffectsTests {
    private let op = RemoveSideEffects()

    @Test("Given no function calls, when visited, then returns no mutations")
    func noFunctionCalls() {
        let source = makeParsedSource("func f() { let x = 1 }")
        #expect(op.mutations(in: source).isEmpty)
    }

    @Test("Given standalone function call, when visited, then produces one mutation")
    func standaloneFunctionCallProducesOneMutation() {
        let source = makeParsedSource("func f() { foo() }")
        let result = op.mutations(in: source)
        #expect(result.count == 1)
        #expect(result[0].replacement == .removeStatement)
        #expect(result[0].mutatedText == "")
    }

    @Test("Given print call, when visited, then produces no mutation")
    func printCallIsIgnored() {
        let source = makeParsedSource(#"func f() { print("hello") }"#)
        #expect(op.mutations(in: source).isEmpty)
    }

    @Test("Given assert call, when visited, then produces no mutation")
    func assertCallIsIgnored() {
        let source = makeParsedSource("func f() { assert(x > 0) }")
        #expect(op.mutations(in: source).isEmpty)
    }

    @Test("Given fatalError call, when visited, then produces no mutation")
    func fatalErrorCallIsIgnored() {
        let source = makeParsedSource(#"func f() { fatalError("oops") }"#)
        #expect(op.mutations(in: source).isEmpty)
    }

    @Test("Given assignment with function call, when visited, then produces no mutation")
    func assignedFunctionCallIsIgnored() {
        let source = makeParsedSource("func f() { let x = foo() }")
        #expect(op.mutations(in: source).isEmpty)
    }

    @Test("Given multiple side-effectful calls, when visited, then produces one mutation per call")
    func multipleSideEffectCallsProduceSeparateMutations() {
        let source = makeParsedSource("func f() { bar(); baz() }")
        let result = op.mutations(in: source)
        #expect(result.count == 2)
    }

    @Test("Given side effect call, when visited, then mutation carries correct operator identifier")
    func mutationCarriesCorrectOperatorIdentifier() {
        let source = makeParsedSource("func f() { notify() }")
        let result = op.mutations(in: source)
        #expect(result[0].operatorIdentifier == "RemoveSideEffects")
    }
}

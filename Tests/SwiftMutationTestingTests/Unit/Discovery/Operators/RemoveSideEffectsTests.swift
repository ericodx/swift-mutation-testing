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

    @Test("Given a standalone call among others, when visited, then produces one mutation")
    func standaloneFunctionCallProducesOneMutation() {
        let source = makeParsedSource("func f() { foo(); other() }")
        let result = op.mutations(in: source)
        #expect(result.count == 2)
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
        let source = makeParsedSource("func f() { notify(); other() }")
        let result = op.mutations(in: source)
        #expect(result[0].operatorIdentifier == "RemoveSideEffects")
    }

    // MARK: - Removing the whole body

    @Test(
        "Given the call is the only statement of a body, when visited, then no mutation is produced",
        arguments: [
            "func f() { foo() }",
            "func f() -> Int { compute() }",
            "init() { setUp() }",
            "deinit { tearDown() }",
            "var x: Int { compute() }",
            "var y: Int { get { compute() } }",
            #"func f() -> [String] { digest.map { String(format: "%02x", $0) } }"#,
            "func f() { list.forEach { handle($0) } }",
            "func f(_ n: Int) { switch n { case 1: foo()\ndefault: bar() } }",
            "func f(_ n: Int) { switch n { case 1: bar()\ndefault: foo() } }",
        ]
    )
    func soleStatementOfABodyIsNotRemoved(code: String) {
        let removed = op.mutations(in: makeParsedSource(code)).map(\.description)
        #expect(!removed.contains { $0.hasPrefix("remove foo") })
    }

    @Test(
        "Given the call is the only statement of a control-flow block, when visited, then it is still removed",
        arguments: [
            "func f() { if cond { foo() }\nbar() }",
            "func f() { for x in xs { foo(x) }\nbar() }",
            "func f() { while cond { foo() }\nbar() }",
            "func f() { do { foo() }\nbar() }",
        ]
    )
    func soleStatementOfAControlFlowBlockIsStillRemoved(code: String) {
        let names = op.mutations(in: makeParsedSource(code)).map(\.description)
        #expect(names.contains { $0.hasPrefix("remove foo") })
    }
}

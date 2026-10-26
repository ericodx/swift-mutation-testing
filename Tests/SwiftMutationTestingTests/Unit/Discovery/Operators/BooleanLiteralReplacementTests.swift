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

    @Test("Given an exhaustive switch over a tuple of booleans, when visited, then skips the literals in its patterns")
    func exhaustiveTupleSwitchPatternsAreSkipped() {
        let source = makeParsedSource(
            """
            func f(a: Bool, b: Bool) -> Int {
                switch (a, b) {
                case (true, true): return 0
                case (true, false): return 1
                case (false, true): return 2
                case (false, false): return 3
                }
            }
            """
        )
        #expect(op.mutations(in: source).isEmpty)
    }

    @Test(
        "Given an exhaustive switch over a boolean, when visited, then skips its patterns and keeps the literals in its bodies"
    )
    func exhaustiveBoolSwitchKeepsBodyLiterals() {
        let source = makeParsedSource(
            """
            func f(a: Bool) -> Bool {
                switch a {
                case true: return false
                case false: return true
                }
            }
            """
        )
        let result = op.mutations(in: source)
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.line == 3 || $0.line == 4 })
        #expect(result.map(\.originalText) == ["false", "true"])
    }

    @Test("Given an exhaustive switch whose patterns mix literals and wildcards, when visited, then skips the literals")
    func wildcardTuplePatternsAreSkipped() {
        let source = makeParsedSource(
            """
            func f(a: Bool, b: Bool, c: Bool) -> Int {
                switch (a, b, c) {
                case (false, true, false): return 0
                case (true, true, _): return 1
                case (false, true, true): return 2
                case (_, false, _): return 3
                }
            }
            """
        )
        #expect(op.mutations(in: source).isEmpty)
    }

    @Test("Given a boolean switch with a default, when visited, then mutates the literals in its patterns")
    func switchWithDefaultIsMutated() {
        let source = makeParsedSource(
            """
            func f(a: Bool, b: Bool) -> Int {
                switch (a, b) {
                case (true, true): return 0
                default: return 1
                }
            }
            """
        )
        #expect(op.mutations(in: source).count == 2)
    }

    @Test("Given a boolean switch with an unknown default, when visited, then mutates the literals in its patterns")
    func switchWithUnknownDefaultIsMutated() {
        let source = makeParsedSource(
            """
            func f(a: Bool) -> Int {
                switch a {
                case true: return 0
                @unknown default: return 1
                }
            }
            """
        )
        #expect(op.mutations(in: source).count == 1)
    }

    @Test(
        "Given a switch with a pattern that is not a boolean literal, when visited, then mutates the boolean patterns")
    func mixedPatternSwitchIsMutated() {
        let source = makeParsedSource(
            """
            func f(a: Bool?) -> Int {
                switch a {
                case true: return 0
                case false: return 1
                case nil: return 2
                }
            }
            """
        )
        #expect(op.mutations(in: source).count == 2)
    }

    @Test("Given a switch with a case made only of wildcards, when visited, then mutates the boolean patterns")
    func allWildcardCaseIsMutated() {
        let source = makeParsedSource(
            """
            func f(a: Bool, b: Bool) -> Int {
                switch (a, b) {
                case (true, true): return 0
                case (_, _): return 1
                }
            }
            """
        )
        #expect(op.mutations(in: source).count == 2)
    }

    @Test("Given a boolean literal in a case's where clause, when visited, then mutates it")
    func whereClauseLiteralIsMutated() {
        let source = makeParsedSource(
            """
            func f(a: Bool, flag: Bool) -> Int {
                switch a {
                case true where flag == true: return 0
                case true: return 1
                case false: return 2
                }
            }
            """
        )
        let result = op.mutations(in: source)
        #expect(result.count == 1)
        #expect(result[0].line == 3)
        #expect(result[0].originalText == "true")
        #expect(result[0].column > 20)
    }

    @Test("Given a boolean literal in an if case pattern, when visited, then mutates it")
    func ifCasePatternIsMutated() {
        let source = makeParsedSource("func f(a: Bool) { if case true = a { } }")
        #expect(op.mutations(in: source).count == 1)
    }
}

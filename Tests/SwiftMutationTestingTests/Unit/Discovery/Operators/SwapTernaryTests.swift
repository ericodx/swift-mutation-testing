import SwiftSyntax
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

    @Test("Given ternary expression, when visited, then the whole ternary is replaced with its branches swapped")
    func mutatedTextHasSwappedBranches() {
        let source = makeParsedSource("func f() { let x = flag ? yes : no }")
        let result = op.mutations(in: source)
        #expect(result.count == 1)
        #expect(result[0].originalText == "flag ? yes : no")
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

    // MARK: - Compound conditions

    @Test(
        "Given a compound condition, when visited, then the whole condition is kept, not just its last operand",
        arguments: [
            (
                #"func f() { let x = sha == ":0" ? a : b }"#,
                #"sha == ":0" ? a : b"#,
                #"sha == ":0" ? b : a"#
            ),
            (
                "func f() { let x = count > 0 ? first : last }",
                "count > 0 ? first : last",
                "count > 0 ? last : first"
            ),
            (
                "func f() { let x = a && b ? yes : no }",
                "a && b ? yes : no",
                "a && b ? no : yes"
            ),
        ]
    )
    func compoundConditionIsPreserved(code: String, original: String, mutated: String) {
        let result = op.mutations(in: makeParsedSource(code))

        #expect(result.count == 1)
        #expect(result[0].originalText == original)
        #expect(result[0].mutatedText == mutated)
    }

    @Test("Given a compound else branch, when visited, then the whole else branch is swapped")
    func compoundElseBranchIsPreserved() {
        let result = op.mutations(in: makeParsedSource("func f() { let x = flag ? a : b + c }"))

        #expect(result.count == 1)
        #expect(result[0].originalText == "flag ? a : b + c")
        #expect(result[0].mutatedText == "flag ? b + c : a")
    }

    // MARK: - Equivalent mutants

    @Test(
        "Given both branches identical, when visited, then no mutation is produced",
        arguments: [
            "func f() { let x = flag ? same : same }",
            "func f() { let x = root.hasSuffix(\"/\") ? root : root }",
        ]
    )
    func identicalBranchesProduceNoMutation(code: String) {
        #expect(op.mutations(in: makeParsedSource(code)).isEmpty)
    }

    // MARK: - Rewriting

    @Test("Given a compound condition, when the mutation is applied, then the result compiles as one ternary")
    func rewritingACompoundConditionLeavesNoTail() {
        let code = #"func f() { let x = sha == ":0" ? a : b }"#
        let result = op.mutations(in: makeParsedSource(code))

        #expect(result.count == 1)
        #expect(
            MutationRewriter().rewrite(source: code, applying: result[0])
                == #"func f() { let x = sha == ":0" ? b : a }"#
        )
    }

    @Test("Given a simple ternary, when the mutation is applied, then only the branches move")
    func rewritingASimpleTernarySwapsBranches() {
        let code = "func f() { let x = flag ? yes : no }"
        let result = op.mutations(in: makeParsedSource(code))

        #expect(
            MutationRewriter().rewrite(source: code, applying: result[0])
                == "func f() { let x = flag ? no : yes }"
        )
    }

    // MARK: - Chained ternaries

    @Test("Given a right-associative chain, when visited, then each ternary keeps its own condition")
    func chainedTernaryKeepsEachCondition() {
        let result = op.mutations(in: makeParsedSource("func f() { let x = a ? b : c ? d : e }"))

        #expect(result.count == 2)
        #expect(result[0].originalText == "a ? b : c ? d : e")
        #expect(result[0].mutatedText == "a ? c ? d : e : b")
        #expect(result[1].originalText == "c ? d : e")
        #expect(result[1].mutatedText == "c ? e : d")
    }

    @Test("Given a chain whose second condition is compound, when visited, then only that condition is taken")
    func chainedTernaryWithCompoundSecondCondition() {
        let result = op.mutations(in: makeParsedSource("func f() { let x = a ? b : c > 0 ? d : e }"))

        #expect(result.count == 2)
        #expect(result[1].originalText == "c > 0 ? d : e")
        #expect(result[1].mutatedText == "c > 0 ? e : d")
    }

    // MARK: - Malformed sources

    @Test(
        "Given a source the parser had to recover from, when visited, then no mutation is produced and nothing crashes",
        arguments: [
            "func f() { let x = a ? b : }",
            "func f() { let x = ? b : c }",
            "func f() { let x = a ? : c }",
            "func f() { let x = a ? b : c ? : }",
            "func f() { let x = ? }",
        ]
    )
    func malformedTernaryProducesNoMutation(code: String) {
        #expect(op.mutations(in: makeParsedSource(code)).allSatisfy { !$0.mutatedText.isEmpty })
    }

    // MARK: - Shapes the parser does not produce

    private func reference(_ name: String) -> ExprSyntax {
        ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(name)))
    }

    private func ternaryNode(then name: String) -> UnresolvedTernaryExprSyntax {
        UnresolvedTernaryExprSyntax(thenExpression: reference(name))
    }

    private func visitorMutations(
        _ build: (SwapTernaryVisitor) -> Void
    ) -> [MutationPoint] {
        let visitor = SwapTernaryVisitor(source: makeParsedSource("func f() {}"))
        build(visitor)
        return visitor.mutations
    }

    @Test("Given a ternary with no expression list parent, when visited, then no mutation is produced")
    func ternaryWithoutExprListParentIsIgnored() {
        let mutations = visitorMutations { visitor in
            _ = visitor.visit(ternaryNode(then: "b"))
        }

        #expect(mutations.isEmpty)
    }

    @Test("Given a ternary with nothing before or after it, when visited, then no mutation is produced")
    func ternaryWithoutConditionOrElseIsIgnored() {
        let leading = ExprListSyntax([ExprSyntax(ternaryNode(then: "b")), reference("c")])
        let trailing = ExprListSyntax([reference("a"), ExprSyntax(ternaryNode(then: "b"))])

        for list in [leading, trailing] {
            let mutations = visitorMutations { visitor in
                for element in list where element.is(UnresolvedTernaryExprSyntax.self) {
                    _ = visitor.visit(element.cast(UnresolvedTernaryExprSyntax.self))
                }
            }
            #expect(mutations.isEmpty)
        }
    }

    @Test("Given two adjacent ternaries, when visited, then the one with an empty condition is ignored")
    func adjacentTernariesLeaveNoEmptyCondition() {
        let list = ExprListSyntax([
            reference("a"),
            ExprSyntax(ternaryNode(then: "b")),
            ExprSyntax(ternaryNode(then: "d")),
            reference("e"),
        ])

        let mutations = visitorMutations { visitor in
            _ = visitor.visit(list[list.index(list.startIndex, offsetBy: 2)].cast(UnresolvedTernaryExprSyntax.self))
        }

        #expect(mutations.isEmpty)
    }
}

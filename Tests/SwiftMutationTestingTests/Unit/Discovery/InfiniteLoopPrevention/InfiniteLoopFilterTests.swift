import Testing

@testable import SwiftMutationTesting

@Suite("InfiniteLoopFilter")
struct InfiniteLoopFilterTests {
    private let filter = InfiniteLoopFilter()
    private let extractor = InfiniteLoopBodyExtractor()

    @Test("Given ArithmeticOperator inside while body, when filtered, then mutation is removed")
    func arithmeticInsideWhileBodyIsFiltered() {
        let code = "func f() { while true { let x = 1 + 2 } }"
        let source = makeParsedSource(code)
        let mutations = ArithmeticOperatorReplacement().mutations(in: source)
        let ranges = extractor.extractLoopBodyRanges(from: source.syntax)

        #expect(!mutations.isEmpty)

        let result = filter.filter(mutations, loopBodyRanges: ranges)
        #expect(result.isEmpty)
    }

    @Test("Given ArithmeticOperator outside loop, when filtered, then mutation is kept")
    func arithmeticOutsideLoopIsNotFiltered() {
        let code = "func f() { let x = 1 + 2 }"
        let source = makeParsedSource(code)
        let mutations = ArithmeticOperatorReplacement().mutations(in: source)
        let ranges = extractor.extractLoopBodyRanges(from: source.syntax)

        #expect(ranges.isEmpty)

        let result = filter.filter(mutations, loopBodyRanges: ranges)
        #expect(result.count == mutations.count)
    }

    @Test("Given RemoveSideEffects inside while body, when filtered, then mutation is removed")
    func removeSideEffectsInsideWhileBodyIsFiltered() {
        let code = "func f() { while true { doWork() } }"
        let source = makeParsedSource(code)
        let mutations = RemoveSideEffects().mutations(in: source)
        let ranges = extractor.extractLoopBodyRanges(from: source.syntax)

        #expect(!mutations.isEmpty)

        let result = filter.filter(mutations, loopBodyRanges: ranges)
        #expect(result.isEmpty)
    }

    @Test("Given BooleanLiteral inside while body, when filtered, then mutation is kept")
    func booleanLiteralInsideWhileBodyIsNotFiltered() {
        let code = "func f() { while true { let x = false } }"
        let source = makeParsedSource(code)
        let mutations = BooleanLiteralReplacement().mutations(in: source)
        let ranges = extractor.extractLoopBodyRanges(from: source.syntax)

        #expect(!mutations.isEmpty)

        let result = filter.filter(mutations, loopBodyRanges: ranges)
        #expect(result.count == mutations.count)
    }

    @Test("Given RelationalOperator in while condition, when filtered, then mutation is kept")
    func relationalInWhileConditionIsNotFiltered() {
        let code = "func f() { while i < 10 { i = i + 1 } }"
        let source = makeParsedSource(code)
        let conditionMutations = RelationalOperatorReplacement().mutations(in: source)
        let ranges = extractor.extractLoopBodyRanges(from: source.syntax)

        #expect(!conditionMutations.isEmpty)

        let result = filter.filter(conditionMutations, loopBodyRanges: ranges)
        #expect(result.count == conditionMutations.count)
    }

    @Test("Given no loop body ranges, when filtered, then returns all mutations unchanged")
    func noLoopRangesReturnsAllMutations() {
        let code = "func f() { let x = 1 + 2 }"
        let source = makeParsedSource(code)
        let mutations = ArithmeticOperatorReplacement().mutations(in: source)

        let result = filter.filter(mutations, loopBodyRanges: [])
        #expect(result.count == mutations.count)
    }

    @Test("Given nested while loops, when filtered, then mutation in inner body is removed")
    func nestedWhileMutationIsFiltered() {
        let code = """
            func f() {
                while true {
                    while false {
                        let x = 1 + 2
                    }
                }
            }
            """
        let source = makeParsedSource(code)
        let mutations = ArithmeticOperatorReplacement().mutations(in: source)
        let ranges = extractor.extractLoopBodyRanges(from: source.syntax)

        #expect(!mutations.isEmpty)

        let result = filter.filter(mutations, loopBodyRanges: ranges)
        #expect(result.isEmpty)
    }

    @Test("Given for-in loop with arithmetic, when filtered, then mutation is kept")
    func forInArithmeticIsNotFiltered() {
        let code = "func f() { for i in 0..<10 { let x = 1 + 2 } }"
        let source = makeParsedSource(code)
        let mutations = ArithmeticOperatorReplacement().mutations(in: source)
        let ranges = extractor.extractLoopBodyRanges(from: source.syntax)

        #expect(ranges.isEmpty)
        #expect(!mutations.isEmpty)

        let result = filter.filter(mutations, loopBodyRanges: ranges)
        #expect(result.count == mutations.count)
    }

    @Test("Given mixed code, when filtered, then only risky mutations inside loop body are removed")
    func mixedCodeFiltersOnlyRiskyInsideLoop() {
        let code = """
            func f() {
                let a = 1 + 2
                while true {
                    let b = 3 + 4
                }
            }
            """
        let source = makeParsedSource(code)
        let mutations = ArithmeticOperatorReplacement().mutations(in: source)
        let ranges = extractor.extractLoopBodyRanges(from: source.syntax)

        #expect(mutations.count >= 2)

        let result = filter.filter(mutations, loopBodyRanges: ranges)
        #expect(result.count == 1)
        #expect(result[0].originalText == "+")
    }
}

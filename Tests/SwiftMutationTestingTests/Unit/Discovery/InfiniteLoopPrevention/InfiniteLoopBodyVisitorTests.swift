import SwiftSyntax
import Testing

@testable import SwiftMutationTesting

@Suite("InfiniteLoopBodyVisitor")
struct InfiniteLoopBodyVisitorTests {
    private let extractor = InfiniteLoopBodyExtractor()

    @Test("Given while loop, when extracted, then returns one body range")
    func whileLoopProducesOneBodyRange() {
        let source = makeParsedSource("func f() { while true { x += 1 } }")
        let ranges = extractor.extractLoopBodyRanges(from: source.syntax)
        #expect(ranges.count == 1)
    }

    @Test("Given repeat-while loop, when extracted, then returns one body range")
    func repeatWhileLoopProducesOneBodyRange() {
        let source = makeParsedSource("func f() { repeat { x += 1 } while true }")
        let ranges = extractor.extractLoopBodyRanges(from: source.syntax)
        #expect(ranges.count == 1)
    }

    @Test("Given for-in loop, when extracted, then returns no ranges")
    func forInLoopProducesNoRanges() {
        let source = makeParsedSource("func f() { for i in 0..<10 { x += 1 } }")
        let ranges = extractor.extractLoopBodyRanges(from: source.syntax)
        #expect(ranges.isEmpty)
    }

    @Test("Given nested while loops, when extracted, then returns two ranges")
    func nestedWhileLoopsProduceTwoRanges() {
        let code = """
            func f() {
                while true {
                    while false {
                        x += 1
                    }
                }
            }
            """
        let source = makeParsedSource(code)
        let ranges = extractor.extractLoopBodyRanges(from: source.syntax)
        #expect(ranges.count == 2)
    }

    @Test("Given while inside for-in, when extracted, then returns one range for while body only")
    func whileInsideForInProducesOneRange() {
        let code = """
            func f() {
                for i in 0..<10 {
                    while true {
                        x += 1
                    }
                }
            }
            """
        let source = makeParsedSource(code)
        let ranges = extractor.extractLoopBodyRanges(from: source.syntax)
        #expect(ranges.count == 1)
    }

    @Test("Given no loops, when extracted, then returns no ranges")
    func noLoopsProducesNoRanges() {
        let source = makeParsedSource("func f() { let x = 1 + 2 }")
        let ranges = extractor.extractLoopBodyRanges(from: source.syntax)
        #expect(ranges.isEmpty)
    }

    @Test("Given while loop, when extracted, then condition is not included in body range")
    func whileConditionIsNotInBodyRange() {
        let code = "func f() { while i < 10 { i = i + 1 } }"
        let source = makeParsedSource(code)
        let ranges = extractor.extractLoopBodyRanges(from: source.syntax)

        let op = RelationalOperatorReplacement()
        let conditionMutations = op.mutations(in: source)
        #expect(!conditionMutations.isEmpty)

        let bodyRange = ranges[0]
        for mutation in conditionMutations {
            let position = AbsolutePosition(utf8Offset: mutation.utf8Offset)
            #expect(!bodyRange.contains(position))
        }
    }
}

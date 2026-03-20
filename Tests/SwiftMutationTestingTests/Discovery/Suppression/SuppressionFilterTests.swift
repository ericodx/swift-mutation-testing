import Testing

@testable import SwiftMutationTesting

@Suite("SuppressionFilter")
struct SuppressionFilterTests {
    private let filter = SuppressionFilter()
    private let extractor = SuppressionAnnotationExtractor()
    private let op = BooleanLiteralReplacement()

    @Test("Given no suppressed ranges, when filtered, then returns all mutations")
    func noRangesReturnAllMutations() {
        let source = makeParsedSource("func f() { let x = true }")
        let mutations = op.mutations(in: source)
        let result = filter.filter(mutations, suppressedRanges: [])
        #expect(result.count == mutations.count)
    }

    @Test("Given annotated function with mutation, when filtered, then returns no mutations")
    func annotatedFunctionYieldsNoMutations() {
        let source = makeParsedSource("@SwiftMutationTestingDisabled func f() { let x = true }")
        let mutations = op.mutations(in: source)
        let ranges = extractor.extractSuppressedRanges(from: source.syntax)
        let result = filter.filter(mutations, suppressedRanges: ranges)
        #expect(result.isEmpty)
    }

    @Test("Given mixed code, when filtered, then returns only mutations outside suppressed scope")
    func mixedCodeReturnsMutationsOutsideSuppressionOnly() {
        let code = """
            @SwiftMutationTestingDisabled func suppressed() { let x = true }
            func active() { let y = false }
            """
        let source = makeParsedSource(code)
        let mutations = op.mutations(in: source)
        let ranges = extractor.extractSuppressedRanges(from: source.syntax)
        let result = filter.filter(mutations, suppressedRanges: ranges)
        #expect(result.count == 1)
        #expect(result[0].originalText == "false")
    }

    @Test("Given annotated type containing method, when filtered, then all mutations inside type are removed")
    func annotatedTypeRemovesAllInnerMutations() {
        let code = """
            @SwiftMutationTestingDisabled struct S {
                func a() { let x = true }
                func b() { let y = false }
            }
            """
        let source = makeParsedSource(code)
        let mutations = op.mutations(in: source)
        let ranges = extractor.extractSuppressedRanges(from: source.syntax)
        let result = filter.filter(mutations, suppressedRanges: ranges)
        #expect(result.isEmpty)
    }

    @Test("Given annotated method inside non-annotated type, when filtered, then removes only that method's mutations")
    func annotatedMethodInsideTypeRemovesOnlyThatMethod() {
        let code = """
            struct S {
                @SwiftMutationTestingDisabled func suppressed() { let x = true }
                func active() { let y = false }
            }
            """
        let source = makeParsedSource(code)
        let mutations = op.mutations(in: source)
        let ranges = extractor.extractSuppressedRanges(from: source.syntax)
        let result = filter.filter(mutations, suppressedRanges: ranges)
        #expect(result.count == 1)
        #expect(result[0].originalText == "false")
    }
}

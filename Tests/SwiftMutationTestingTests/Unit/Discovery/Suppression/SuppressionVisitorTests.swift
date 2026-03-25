import Testing

@testable import SwiftMutationTesting

@Suite("SuppressionVisitor")
struct SuppressionVisitorTests {
    private let extractor = SuppressionAnnotationExtractor()

    @Test("Given annotated enum, when extracted, then returns one range")
    func annotatedEnumProducesOneRange() {
        let source = makeParsedSource("@SwiftMutationTestingDisabled enum E { case a, b }")
        let ranges = extractor.extractSuppressedRanges(from: source.syntax)
        #expect(ranges.count == 1)
    }

    @Test("Given unannotated enum, when extracted, then returns no ranges")
    func unannotatedEnumProducesNoRanges() {
        let source = makeParsedSource("enum E { case a, b }")
        let ranges = extractor.extractSuppressedRanges(from: source.syntax)
        #expect(ranges.isEmpty)
    }

    @Test("Given annotated variable, when extracted, then returns one range")
    func annotatedVariableProducesOneRange() {
        let source = makeParsedSource("@SwiftMutationTestingDisabled var x = true")
        let ranges = extractor.extractSuppressedRanges(from: source.syntax)
        #expect(ranges.count == 1)
    }

    @Test("Given unannotated variable, when extracted, then returns no ranges")
    func unannotatedVariableProducesNoRanges() {
        let source = makeParsedSource("var x = true")
        let ranges = extractor.extractSuppressedRanges(from: source.syntax)
        #expect(ranges.isEmpty)
    }

    @Test("Given closure inside non-annotated function, when extracted, then returns no ranges")
    func closureInsideNonAnnotatedFunctionProducesNoRanges() {
        let source = makeParsedSource("func f() { let g: () -> Void = { } }")
        let ranges = extractor.extractSuppressedRanges(from: source.syntax)
        #expect(ranges.isEmpty)
    }

    @Test("Given annotated struct containing closure, when extracted, then returns one range for struct only")
    func annotatedStructWithClosureProducesOneRange() {
        let code = """
            @SwiftMutationTestingDisabled struct S {
                let compute: () -> Int = { 42 }
            }
            """
        let source = makeParsedSource(code)
        let ranges = extractor.extractSuppressedRanges(from: source.syntax)
        #expect(ranges.count == 1)
    }

    @Test("Given annotated function, when extracted, then returns one range")
    func annotatedFunctionProducesOneRange() {
        let source = makeParsedSource("@SwiftMutationTestingDisabled func f() { }")
        let ranges = extractor.extractSuppressedRanges(from: source.syntax)
        #expect(ranges.count == 1)
    }

    @Test("Given unannotated function, when extracted, then returns no ranges")
    func unannotatedFunctionProducesNoRanges() {
        let source = makeParsedSource("func f() { }")
        let ranges = extractor.extractSuppressedRanges(from: source.syntax)
        #expect(ranges.isEmpty)
    }

    @Test("Given annotated class, when extracted, then returns one range")
    func annotatedClassProducesOneRange() {
        let source = makeParsedSource("@SwiftMutationTestingDisabled class C { }")
        let ranges = extractor.extractSuppressedRanges(from: source.syntax)
        #expect(ranges.count == 1)
    }

    @Test("Given unannotated class, when extracted, then returns no ranges")
    func unannotatedClassProducesNoRanges() {
        let source = makeParsedSource("class C { }")
        let ranges = extractor.extractSuppressedRanges(from: source.syntax)
        #expect(ranges.isEmpty)
    }

    @Test("Given annotated extension, when extracted, then returns one range")
    func annotatedExtensionProducesOneRange() {
        let source = makeParsedSource("@SwiftMutationTestingDisabled extension String { }")
        let ranges = extractor.extractSuppressedRanges(from: source.syntax)
        #expect(ranges.count == 1)
    }

    @Test("Given unannotated extension, when extracted, then returns no ranges")
    func unannotatedExtensionProducesNoRanges() {
        let source = makeParsedSource("extension String { }")
        let ranges = extractor.extractSuppressedRanges(from: source.syntax)
        #expect(ranges.isEmpty)
    }

    @Test("Given function with conditional compilation block in attribute list, when extracted, then returns no ranges")
    func functionWithIfConfigInAttributeListProducesNoRanges() {
        let code = """
            #if canImport(Foundation)
            @available(macOS 10, *)
            #endif
            func foo() {}
            """
        let source = makeParsedSource(code)
        let ranges = extractor.extractSuppressedRanges(from: source.syntax)
        #expect(ranges.isEmpty)
    }
}

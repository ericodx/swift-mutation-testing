import Testing

@testable import SwiftMutationTesting

@Suite("SuppressionAnnotationExtractor")
struct SuppressionAnnotationExtractorTests {
    private let extractor = SuppressionAnnotationExtractor()

    @Test("Given function without annotation, when extracted, then returns no ranges")
    func noAnnotationProducesNoRanges() {
        let source = makeParsedSource("func f() { let x = true }")
        let ranges = extractor.extractSuppressedRanges(from: source.syntax)
        #expect(ranges.isEmpty)
    }

    @Test("Given function with annotation, when extracted, then returns one range")
    func annotatedFunctionProducesOneRange() {
        let source = makeParsedSource("@SwiftMutationTestingDisabled func f() { let x = true }")
        let ranges = extractor.extractSuppressedRanges(from: source.syntax)
        #expect(ranges.count == 1)
    }

    @Test("Given annotated struct, when extracted, then returns one range")
    func annotatedStructProducesOneRange() {
        let source = makeParsedSource("@SwiftMutationTestingDisabled struct S { var x = true }")
        let ranges = extractor.extractSuppressedRanges(from: source.syntax)
        #expect(ranges.count == 1)
    }

    @Test("Given annotated class, when extracted, then returns one range")
    func annotatedClassProducesOneRange() {
        let source = makeParsedSource("@SwiftMutationTestingDisabled class C { var x = true }")
        let ranges = extractor.extractSuppressedRanges(from: source.syntax)
        #expect(ranges.count == 1)
    }

    @Test("Given annotated extension, when extracted, then returns one range")
    func annotatedExtensionProducesOneRange() {
        let source = makeParsedSource("@SwiftMutationTestingDisabled extension Int { func f() { } }")
        let ranges = extractor.extractSuppressedRanges(from: source.syntax)
        #expect(ranges.count == 1)
    }

    @Test("Given two annotated functions, when extracted, then returns two ranges")
    func twoAnnotatedFunctionsProduceTwoRanges() {
        let code = """
            @SwiftMutationTestingDisabled func f() { let x = true }
            @SwiftMutationTestingDisabled func g() { let y = false }
            """
        let source = makeParsedSource(code)
        let ranges = extractor.extractSuppressedRanges(from: source.syntax)
        #expect(ranges.count == 2)
    }

    @Test("Given annotated type containing method, when extracted, then returns one range for type only")
    func annotatedTypeWithMethodProducesOneRange() {
        let code = """
            @SwiftMutationTestingDisabled struct S {
                func method() { let x = true }
            }
            """
        let source = makeParsedSource(code)
        let ranges = extractor.extractSuppressedRanges(from: source.syntax)
        #expect(ranges.count == 1)
    }
}

import Testing

@testable import SwiftMutationTesting

@Suite("MutationRewriter")
struct MutationRewriterTests {
    private let rewriter = MutationRewriter()

    @Test("Given source and mutation, when rewritten, then original text is replaced with mutated text")
    func appliesTextReplacement() {
        let source = makeParsedSource("func f() { let x = true }")
        let mutation = BooleanLiteralReplacement().mutations(in: source)[0]
        let result = rewriter.rewrite(source: source.file.content, applying: mutation)
        #expect(result.contains("false"))
        #expect(!result.contains(" true"))
    }

    @Test("Given mutation with empty mutatedText, when rewritten, then original text is removed")
    func removesOriginalTextWhenMutatedTextIsEmpty() {
        let source = makeParsedSource("func f() { notify() }")
        let mutation = RemoveSideEffects().mutations(in: source)[0]
        let result = rewriter.rewrite(source: source.file.content, applying: mutation)
        #expect(!result.contains("notify()"))
    }

    @Test("Given multiple replacements possible, when rewritten, then only one occurrence is replaced")
    func replacesOnlyOneOccurrence() {
        let source = makeParsedSource("func f() { let a = true; let b = true }")
        let mutations = BooleanLiteralReplacement().mutations(in: source)
        #expect(mutations.count == 2)
        let result = rewriter.rewrite(source: source.file.content, applying: mutations[0])
        let falseCount = result.components(separatedBy: "false").count - 1
        #expect(falseCount == 1)
    }

    @Test("Given out-of-bounds offset, when rewritten, then returns original source unchanged")
    func outOfBoundsOffsetReturnsOriginal() {
        let source = "func f() { }"
        let mutation = MutationPoint(
            operatorIdentifier: "Test",
            filePath: "test.swift",
            line: 1,
            column: 1,
            utf8Offset: 9999,
            originalText: "true",
            mutatedText: "false",
            replacement: .booleanLiteral,
            description: "test"
        )
        let result = rewriter.rewrite(source: source, applying: mutation)
        #expect(result == source)
    }
}

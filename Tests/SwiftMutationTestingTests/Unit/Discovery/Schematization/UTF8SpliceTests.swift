import Testing

@testable import SwiftMutationTesting

@Suite("UTF8Splice")
struct UTF8SpliceTests {

    @Test("Given a byte range inside the text, when it is read, then the bytes come back as text")
    func substringReadsTheRange() {
        #expect(UTF8Splice.substring(of: "let café = 1", from: 4, to: 9) == "café")
    }

    @Test("Given a byte range inside the text, when it is replaced, then only those bytes change")
    func replacingChangesOnlyTheRange() {
        #expect(UTF8Splice.replacing(from: 6, to: 8, in: "a = b && c", with: "||") == "a = b || c")
    }

    @Test("Given an offset, when text is inserted, then it lands before the byte at that offset")
    func insertingPutsTheTextAtTheOffset() {
        #expect(UTF8Splice.inserting("f(); ", at: 0, in: "g()") == "f(); g()")
        #expect(UTF8Splice.inserting("!", at: 3, in: "g()") == "g()!")
    }

    @Test(
        "Given a range that does not lie inside the text, when it is read or replaced, then there is no result",
        arguments: [(-1, 2), (2, 1), (0, 4)]
    )
    func aRangeOutsideTheTextHasNoResult(start: Int, end: Int) {
        #expect(UTF8Splice.substring(of: "abc", from: start, to: end) == nil)
        #expect(UTF8Splice.replacing(from: start, to: end, in: "abc", with: "x") == nil)
    }

    @Test("Given a range that cuts through a character, when it is read or replaced, then there is no result")
    func aRangeCuttingACharacterHasNoResult() {
        #expect(UTF8Splice.substring(of: "é", from: 0, to: 1) == nil)
        #expect(UTF8Splice.replacing(from: 0, to: 1, in: "é", with: "e") == nil)
    }

    @Test("Given bytes, when a range is replaced, then it is text, or nothing out of range or mid-character")
    func bytesAreSplicedLikeText() {
        let bytes = Array("a é b".utf8)

        #expect(UTF8Splice.replacing(from: 0, to: 1, in: bytes, with: "x") == "x é b")
        #expect(UTF8Splice.replacing(from: 2, to: 3, in: bytes, with: "x") == nil)
        #expect(UTF8Splice.replacing(from: 4, to: 99, in: bytes, with: "x") == nil)
        #expect(UTF8Splice.isRange(from: 0, to: bytes.count, in: bytes))
        #expect(!UTF8Splice.isRange(from: 3, to: 2, in: bytes))
    }
}

import Testing

@testable import SwiftMutationTesting

@Suite("MutantCacheKey")
struct MutantCacheKeyTests {
    @Test("Given a mutant descriptor, when make called, then key fields are populated from descriptor")
    func makePopulatesFieldsFromDescriptor() {
        let mutant = MutantDescriptor(
            id: "m0",
            filePath: "/tmp/Foo.swift",
            line: 1,
            column: 3,
            utf8Offset: 42,
            originalText: "a + b",
            mutatedText: "a - b",
            operatorIdentifier: "binaryOperator",
            replacementKind: .binaryOperator,
            description: "Replace + with -",
            isSchematizable: false,
            mutatedSourceContent: nil
        )

        let key = MutantCacheKey.make(for: mutant, testFilesHash: "testhash")

        #expect(key.testFilesHash == "testhash")
        #expect(key.operatorIdentifier == "binaryOperator")
        #expect(key.utf8Offset == 42)
        #expect(key.originalText == "a + b")
        #expect(key.mutatedText == "a - b")
    }

    @Test("Given same content string, when hash called twice, then identical hashes are returned")
    func hashOfIsStable() {
        let first = MutantCacheKey.hash(of: "content")
        let second = MutantCacheKey.hash(of: "content")

        #expect(first == second)
        #expect(first.count == 64)
    }

    @Test("Given two identical mutant descriptors, when make called, then equal keys are produced")
    func identicalDescriptorsProduceEqualKeys() {
        let mutant = MutantDescriptor(
            id: "m0",
            filePath: "/tmp/Foo.swift",
            line: 1,
            column: 1,
            utf8Offset: 0,
            originalText: "x",
            mutatedText: "y",
            operatorIdentifier: "op",
            replacementKind: .binaryOperator,
            description: "desc",
            isSchematizable: false,
            mutatedSourceContent: nil
        )

        let keyA = MutantCacheKey.make(for: mutant, testFilesHash: "h")
        let keyB = MutantCacheKey.make(for: mutant, testFilesHash: "h")

        #expect(keyA == keyB)
    }

    @Test("Given different utf8Offsets, when make called, then different keys are produced")
    func differentOffsetProducesDifferentKey() {
        let base = MutantDescriptor(
            id: "m0",
            filePath: "/tmp/Foo.swift",
            line: 1,
            column: 1,
            utf8Offset: 0,
            originalText: "a",
            mutatedText: "b",
            operatorIdentifier: "op",
            replacementKind: .binaryOperator,
            description: "desc",
            isSchematizable: false,
            mutatedSourceContent: nil
        )
        let shifted = MutantDescriptor(
            id: "m1",
            filePath: "/tmp/Foo.swift",
            line: 1,
            column: 5,
            utf8Offset: 10,
            originalText: "a",
            mutatedText: "b",
            operatorIdentifier: "op",
            replacementKind: .binaryOperator,
            description: "desc",
            isSchematizable: false,
            mutatedSourceContent: nil
        )

        let keyBase = MutantCacheKey.make(for: base, testFilesHash: "h")
        let keyShifted = MutantCacheKey.make(for: shifted, testFilesHash: "h")
        #expect(keyBase != keyShifted)
    }
}

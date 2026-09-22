@testable import SwiftMutationTesting

func makeMutantCacheKey(
    filePath: String = "/tmp/Foo.swift",
    fileContentHash: String = "abc",
    operatorIdentifier: String = "binaryOperator",
    utf8Offset: Int = 0,
    originalText: String = "a + b",
    mutatedText: String = "a - b"
) -> MutantCacheKey {
    MutantCacheKey(
        filePath: filePath,
        fileContentHash: fileContentHash,
        operatorIdentifier: operatorIdentifier,
        utf8Offset: utf8Offset,
        originalText: originalText,
        mutatedText: mutatedText
    )
}

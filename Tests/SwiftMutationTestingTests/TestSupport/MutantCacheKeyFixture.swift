@testable import SwiftMutationTesting

func makeMutantCacheKey(
    fileContentHash: String = "abc",
    operatorIdentifier: String = "binaryOperator",
    utf8Offset: Int = 0,
    originalText: String = "a + b",
    mutatedText: String = "a - b"
) -> MutantCacheKey {
    MutantCacheKey(
        fileContentHash: fileContentHash,
        operatorIdentifier: operatorIdentifier,
        utf8Offset: utf8Offset,
        originalText: originalText,
        mutatedText: mutatedText
    )
}

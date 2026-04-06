import CryptoKit
import Foundation

struct MutantCacheKey: Hashable, Sendable, Codable {
    let fileContentHash: String
    let operatorIdentifier: String
    let utf8Offset: Int
    let originalText: String
    let mutatedText: String

    static func hash(of content: String) -> String {
        let digest = SHA256.hash(data: Data(content.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func make(for mutant: MutantDescriptor) -> MutantCacheKey {
        let content = mutant.mutatedSourceContent ?? mutant.filePath
        return MutantCacheKey(
            fileContentHash: hash(of: content),
            operatorIdentifier: mutant.operatorIdentifier,
            utf8Offset: mutant.utf8Offset,
            originalText: mutant.originalText,
            mutatedText: mutant.mutatedText
        )
    }
}

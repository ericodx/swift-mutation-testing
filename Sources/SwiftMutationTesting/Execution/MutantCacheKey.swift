import CryptoKit
import Foundation

struct MutantCacheKey: Sendable {
    let fileContentHash: String
    let testFilesHash: String
    let mutantID: String

    var value: String {
        let combined = "\(fileContentHash):\(testFilesHash):\(mutantID)"
        let digest = SHA256.hash(data: Data(combined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func make(for mutant: MutantDescriptor, testFilesHash: String) -> MutantCacheKey {
        let content = mutant.mutatedSourceContent ?? mutant.filePath
        let digest = SHA256.hash(data: Data(content.utf8))
        let fileHash = digest.map { String(format: "%02x", $0) }.joined()
        return MutantCacheKey(fileContentHash: fileHash, testFilesHash: testFilesHash, mutantID: mutant.id)
    }
}

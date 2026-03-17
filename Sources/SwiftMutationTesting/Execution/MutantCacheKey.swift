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
}

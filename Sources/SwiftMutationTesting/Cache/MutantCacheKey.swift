import CryptoKit
import Foundation

struct MutantCacheKey: Hashable, Sendable, Codable {
    let filePath: String
    let fileContentHash: String
    let operatorIdentifier: String
    let utf8Offset: Int
    let originalText: String
    let mutatedText: String

    static func hash(of content: String) -> String {
        let digest = SHA256.hash(data: Data(content.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// The key a mutant's verdict is cached under.
    ///
    /// `fileContentHash` used to fall back to the file *path* whenever a mutant carried no mutated
    /// source — which is every schematizable mutant, the majority of a run. A path is a constant,
    /// so editing the code under test left the key unchanged and the stale verdict was replayed
    /// (issue #79). The descriptor now carries the hash of the unmutated file instead.
    ///
    /// The path stays in the key beside it. Content alone would collide for two byte-identical
    /// files — generated sources, boilerplate — whose mutants are not interchangeable because they
    /// compile into different places. Renaming a file therefore re-measures its mutants, which is
    /// the conservative direction to be wrong in.
    static func make(for mutant: MutantDescriptor) -> MutantCacheKey {
        MutantCacheKey(
            filePath: mutant.filePath,
            fileContentHash: mutant.sourceContentHash,
            operatorIdentifier: mutant.operatorIdentifier,
            utf8Offset: mutant.utf8Offset,
            originalText: mutant.originalText,
            mutatedText: mutant.mutatedText
        )
    }
}

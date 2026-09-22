struct MutantDescriptor: Sendable, Codable {
    let id: String
    let filePath: String
    let line: Int
    let column: Int
    let utf8Offset: Int
    let originalText: String
    let mutatedText: String
    let operatorIdentifier: String
    let replacementKind: ReplacementKind
    let description: String
    let isSchematizable: Bool
    let mutatedSourceContent: String?

    /// Hash of the unmutated file this mutant was found in, taken at discovery.
    ///
    /// The cache is keyed on it, so that editing the code under test invalidates the verdicts
    /// measured against the old code. Carried on the descriptor rather than read back from disk
    /// because discovery already has the contents in hand, and reading per mutant would re-read the
    /// same file once for each mutation found in it (issue #79).
    let sourceContentHash: String
}

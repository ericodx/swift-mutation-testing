struct MutationPoint: Sendable {
    let operatorIdentifier: String
    let filePath: String
    let line: Int
    let column: Int
    let utf8Offset: Int
    let originalText: String
    let mutatedText: String
    let replacement: ReplacementKind
    let description: String
}

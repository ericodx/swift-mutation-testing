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

    static func inSourceOrder(_ lhs: MutationPoint, _ rhs: MutationPoint) -> Bool {
        (lhs.filePath, lhs.utf8Offset) < (rhs.filePath, rhs.utf8Offset)
    }
}

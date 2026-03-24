struct SonarRange: Sendable, Encodable {
    let startLine: Int
    let endLine: Int
    let startColumn: Int
    let endColumn: Int
}

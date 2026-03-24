struct SonarLocation: Sendable, Encodable {
    let message: String
    let filePath: String
    let textRange: SonarRange
}

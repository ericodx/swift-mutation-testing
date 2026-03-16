struct SchematizedFile: Sendable, Codable {
    let originalPath: String
    let schematizedContent: String
}

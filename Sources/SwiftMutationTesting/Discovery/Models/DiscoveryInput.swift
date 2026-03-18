struct DiscoveryInput: Sendable {
    let projectPath: String
    let sourcesPath: String
    let excludePatterns: [String]
    let operators: [String]
}

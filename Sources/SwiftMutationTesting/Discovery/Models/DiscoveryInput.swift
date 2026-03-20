struct DiscoveryInput: Sendable {
    let projectPath: String
    let scheme: String
    let destination: String
    let timeout: Double
    let concurrency: Int
    let noCache: Bool
    let sourcesPath: String
    let excludePatterns: [String]
    let operators: [String]
}

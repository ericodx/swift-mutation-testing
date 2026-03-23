struct RunnerInput: Sendable {
    let projectPath: String
    let scheme: String
    let destination: String
    let timeout: Double
    let concurrency: Int
    let noCache: Bool
    let schematizedFiles: [SchematizedFile]
    let supportFileContent: String
    let mutants: [MutantDescriptor]
}

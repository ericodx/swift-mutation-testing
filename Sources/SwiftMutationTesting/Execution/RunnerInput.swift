struct RunnerInput: Sendable {
    let projectPath: String
    let projectType: ProjectType
    let timeout: Double
    let concurrency: Int
    let noCache: Bool
    let schematizedFiles: [SchematizedFile]
    let mutants: [MutantDescriptor]
    var importStyle: ImportStyle = .implicit
    var sourceHashes: [String: String] = [:]
}

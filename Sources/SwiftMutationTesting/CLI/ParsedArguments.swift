struct ParsedArguments: Sendable {
    enum Command: Sendable, Equatable {
        case run
        case plan
        case merge
        case reproduce
        case initialize
        case help
        case version
    }

    var command: Command = .run
    var projectPath: String = "."
    var plan: PlanOptions = PlanOptions()
    var build: BuildOptions = BuildOptions()
    var reporting: ReportingOptions = ReportingOptions()
    var filter: FilterOptions = FilterOptions()
    var gate: GateOptions = GateOptions()

    struct BuildOptions: Sendable {
        var scheme: String?
        var destination: String?
        var testTarget: String?
        var timeout: Double?
        var buildTimeout: Double?
        var concurrency: Int?
        var noCache: Bool = false
        var testingFramework: String?
        var workspace: String?
        var xcodeProject: String?
        var xcodebuildArguments: [String] = []
    }

    struct ReportingOptions: Sendable {
        var outputs: [ReportFormat: String] = [:]
        var keepLogsPath: String?
        var quiet: Bool = false
    }

    struct FilterOptions: Sendable {
        var sourcesPath: String?
        var excludePatterns: [String] = []
        var operators: [String] = []
        var disabledMutators: [String] = []
        var operatorTier: String?
    }

    struct PlanOptions: Sendable {
        var path: String?
        var shard: Shard?
        var results: [String] = []
        var mutant: String?
        var projectPath: String?
    }

    struct GateOptions: Sendable {
        var minScore: Double?
        var baseline: String?
        var maxScoreDrop: Double?
        var maxNewSurvivors: Int?
        var maxIntegrityWarnings: Int?
        var writeBaseline: String?
    }
}

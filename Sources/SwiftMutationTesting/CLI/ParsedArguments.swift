struct ParsedArguments: Sendable {
    init(
        projectPath: String = ".",
        scheme: String? = nil,
        destination: String? = nil,
        testTarget: String? = nil,
        timeout: Double? = nil,
        concurrency: Int? = nil,
        noCache: Bool = false,
        output: String? = nil,
        htmlOutput: String? = nil,
        sonarOutput: String? = nil,
        quiet: Bool = false,
        sourcesPath: String? = nil,
        excludePatterns: [String] = [],
        operators: [String] = [],
        disabledMutators: [String] = [],
        showVersion: Bool = false,
        showHelp: Bool = false,
        showInit: Bool = false
    ) {
        self.projectPath = projectPath
        self.scheme = scheme
        self.destination = destination
        self.testTarget = testTarget
        self.timeout = timeout
        self.concurrency = concurrency
        self.noCache = noCache
        self.output = output
        self.htmlOutput = htmlOutput
        self.sonarOutput = sonarOutput
        self.quiet = quiet
        self.sourcesPath = sourcesPath
        self.excludePatterns = excludePatterns
        self.operators = operators
        self.disabledMutators = disabledMutators
        self.showVersion = showVersion
        self.showHelp = showHelp
        self.showInit = showInit
    }

    let projectPath: String
    let scheme: String?
    let destination: String?
    let testTarget: String?
    let timeout: Double?
    let concurrency: Int?
    let noCache: Bool
    let output: String?
    let htmlOutput: String?
    let sonarOutput: String?
    let quiet: Bool
    let sourcesPath: String?
    let excludePatterns: [String]
    let operators: [String]
    let disabledMutators: [String]
    let showVersion: Bool
    let showHelp: Bool
    let showInit: Bool
}

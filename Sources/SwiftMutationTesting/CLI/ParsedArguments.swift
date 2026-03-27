struct ParsedArguments: Sendable {
    init(
        projectPath: String = ".",
        showVersion: Bool = false,
        showHelp: Bool = false,
        showInit: Bool = false,
        build: BuildOptions = BuildOptions(),
        reporting: ReportingOptions = ReportingOptions(),
        filter: FilterOptions = FilterOptions()
    ) {
        self.projectPath = projectPath
        self.showVersion = showVersion
        self.showHelp = showHelp
        self.showInit = showInit
        self.build = build
        self.reporting = reporting
        self.filter = filter
    }

    var projectPath: String
    var showVersion: Bool
    var showHelp: Bool
    var showInit: Bool
    var build: BuildOptions
    var reporting: ReportingOptions
    var filter: FilterOptions

    struct BuildOptions: Sendable {
        init(
            scheme: String? = nil,
            destination: String? = nil,
            testTarget: String? = nil,
            timeout: Double? = nil,
            concurrency: Int? = nil,
            noCache: Bool = false
        ) {
            self.scheme = scheme
            self.destination = destination
            self.testTarget = testTarget
            self.timeout = timeout
            self.concurrency = concurrency
            self.noCache = noCache
        }

        var scheme: String?
        var destination: String?
        var testTarget: String?
        var timeout: Double?
        var concurrency: Int?
        var noCache: Bool
    }

    struct ReportingOptions: Sendable {
        init(output: String? = nil, htmlOutput: String? = nil, sonarOutput: String? = nil, quiet: Bool = false) {
            self.output = output
            self.htmlOutput = htmlOutput
            self.sonarOutput = sonarOutput
            self.quiet = quiet
        }

        var output: String?
        var htmlOutput: String?
        var sonarOutput: String?
        var quiet: Bool
    }

    struct FilterOptions: Sendable {
        init(
            sourcesPath: String? = nil,
            excludePatterns: [String] = [],
            operators: [String] = [],
            disabledMutators: [String] = []
        ) {
            self.sourcesPath = sourcesPath
            self.excludePatterns = excludePatterns
            self.operators = operators
            self.disabledMutators = disabledMutators
        }

        var sourcesPath: String?
        var excludePatterns: [String]
        var operators: [String]
        var disabledMutators: [String]
    }
}

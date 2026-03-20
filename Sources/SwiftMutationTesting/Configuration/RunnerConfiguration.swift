import Foundation

struct RunnerConfiguration: Sendable {

    init(
        projectPath: String,
        scheme: String,
        destination: String,
        testTarget: String? = nil,
        timeout: Double,
        concurrency: Int,
        noCache: Bool,
        output: String? = nil,
        htmlOutput: String? = nil,
        sonarOutput: String? = nil,
        quiet: Bool,
        sourcesPath: String? = nil,
        excludePatterns: [String] = [],
        operators: [String] = []
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
    }

    static let defaultTimeout: Double = 60.0
    static let defaultConcurrency: Int = max(1, ProcessInfo.processInfo.processorCount - 1)

    let projectPath: String
    let scheme: String
    let destination: String
    let testTarget: String?
    let timeout: Double
    let concurrency: Int
    let noCache: Bool
    let output: String?
    let htmlOutput: String?
    let sonarOutput: String?
    let quiet: Bool
    let sourcesPath: String?
    let excludePatterns: [String]
    let operators: [String]
}

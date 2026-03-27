import Foundation

struct RunnerConfiguration: Sendable {
    static let defaultTimeout: Double = 60.0
    static let defaultConcurrency: Int = max(1, ProcessInfo.processInfo.processorCount - 1)

    let projectPath: String
    let build: BuildOptions
    let reporting: ReportingOptions
    let filter: FilterOptions

    struct BuildOptions: Sendable {
        var scheme: String
        var destination: String
        var testTarget: String?
        var timeout: Double
        var concurrency: Int
        var noCache: Bool
    }

    struct ReportingOptions: Sendable {
        var output: String?
        var htmlOutput: String?
        var sonarOutput: String?
        var quiet: Bool
    }

    struct FilterOptions: Sendable {
        var sourcesPath: String?
        var excludePatterns: [String]
        var operators: [String]
    }
}

import Foundation

struct RunnerConfiguration: Sendable {
    static let defaultXcodeTimeout: Double = 120.0
    static let defaultSPMTimeout: Double = 30.0
    static let defaultConcurrency: Int = max(1, ProcessInfo.processInfo.processorCount - 1)

    let projectPath: String
    let build: BuildOptions
    let reporting: ReportingOptions
    let filter: FilterOptions

    struct BuildOptions: Sendable {
        var projectType: ProjectType
        var testTarget: String?
        var timeout: Double
        var concurrency: Int
        var noCache: Bool
        var testingFramework: TestingFramework = .swiftTesting
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

import Foundation

struct RunnerConfiguration: Sendable {
    static let defaultXcodeTimeout: Double = 120.0
    static let defaultSPMTimeout: Double = 30.0
    static let defaultBuildTimeout: Double = 120.0
    static let defaultConcurrency = concurrency(forProcessors: ProcessInfo.processInfo.processorCount)

    static func concurrency(forProcessors processorCount: Int) -> Int {
        max(1, processorCount - 1)
    }

    let projectPath: String
    var build: BuildOptions
    var reporting: ReportingOptions
    var filter: FilterOptions
    var gate: GateOptions = GateOptions()

    struct BuildOptions: Sendable {
        var projectType: ProjectType
        var xcodeContainer: XcodeContainer?
        var xcodebuildArguments: [String]
        var testTarget: String?
        var timeout: Double
        var buildTimeout: Double
        var concurrency: Int
        var noCache: Bool
        var testingFramework: TestingFramework = .swiftTesting
        var reproduction: Reproduction?

        var reproducing: Bool { reproduction != nil }

        var xcodeArguments: [String] {
            (xcodeContainer?.arguments ?? []) + xcodebuildArguments
        }
    }

    struct ReportingOptions: Sendable {
        var outputs: [ReportFormat: String] = [:]
        var keepLogsPath: String?
        var quiet: Bool
        var timing: Bool = false
    }

    struct FilterOptions: Sendable {
        var sourcesPath: String?
        var excludePatterns: [String]
        var operators: [String]
    }

    struct GateOptions: Sendable {
        var policy = GatePolicy()
        var baselinePath: String?
        var writeBaselinePath: String?

        var isActive: Bool {
            !policy.isEmpty || baselinePath != nil
        }
    }
}

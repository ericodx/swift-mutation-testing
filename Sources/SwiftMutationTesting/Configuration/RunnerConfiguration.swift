import Foundation

struct RunnerConfiguration: Sendable {
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
}

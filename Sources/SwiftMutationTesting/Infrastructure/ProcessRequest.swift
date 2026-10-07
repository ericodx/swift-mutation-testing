import Foundation

struct ProcessRequest: Sendable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]?
    let additionalEnvironment: [String: String]
    let workingDirectoryURL: URL
    var timeout: Double
    var stopRule: OutputStopRule?

    func withTimeout(_ timeout: Double) -> ProcessRequest {
        var copy = self
        copy.timeout = timeout
        return copy
    }

    func stopping(at rule: OutputStopRule) -> ProcessRequest {
        var copy = self
        copy.stopRule = rule
        return copy
    }
}

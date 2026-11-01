import Foundation

struct ProcessRequest: Sendable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]?
    var additionalEnvironment: [String: String]
    let workingDirectoryURL: URL
    var timeout: Double
    var stopRule: OutputStopRule?
    var discardsStandardError = false
    var outputURL: URL?

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

    func discardingStandardError() -> ProcessRequest {
        var copy = self
        copy.discardsStandardError = true
        return copy
    }

    func capturingOutput(at url: URL) -> ProcessRequest {
        var copy = self
        copy.outputURL = url
        return copy
    }
}

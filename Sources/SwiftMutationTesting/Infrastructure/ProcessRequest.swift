import Foundation

struct ProcessRequest: Sendable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]?
    let additionalEnvironment: [String: String]
    let workingDirectoryURL: URL
    let timeout: Double

    /// The same request with a different deadline, for when several requests share one budget.
    func withTimeout(_ timeout: Double) -> ProcessRequest {
        ProcessRequest(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            additionalEnvironment: additionalEnvironment,
            workingDirectoryURL: workingDirectoryURL,
            timeout: timeout
        )
    }
}

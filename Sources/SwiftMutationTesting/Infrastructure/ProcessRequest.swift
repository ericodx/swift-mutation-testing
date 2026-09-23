import Foundation

struct ProcessRequest: Sendable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]?
    let additionalEnvironment: [String: String]
    let workingDirectoryURL: URL
    let timeout: Double

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

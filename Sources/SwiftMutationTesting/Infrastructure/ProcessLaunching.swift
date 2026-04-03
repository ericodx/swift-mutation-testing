import Foundation

struct CapturedOutput: Sendable {
    let exitCode: Int32
    let output: String
    let cleanup: @Sendable () -> Void
}

protocol ProcessLaunching: Sendable {
    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32

    func launchCapturing(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        additionalEnvironment: [String: String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> (exitCode: Int32, output: String)

    func launchCapturingDeferred(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        additionalEnvironment: [String: String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> CapturedOutput
}

extension ProcessLaunching {
    func launchCapturingDeferred(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        additionalEnvironment: [String: String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> CapturedOutput {
        let result = try await launchCapturing(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            additionalEnvironment: additionalEnvironment,
            workingDirectoryURL: workingDirectoryURL,
            timeout: timeout
        )
        return CapturedOutput(exitCode: result.exitCode, output: result.output, cleanup: {})
    }
}

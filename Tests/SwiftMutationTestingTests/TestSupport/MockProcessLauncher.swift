import Foundation

@testable import SwiftMutationTesting

struct MockProcessLauncher: ProcessLaunching {

    init(
        exitCode: Int32,
        output: String = "",
        responses: [String: (exitCode: Int32, output: String)] = [:],
        throwsOnCapture: Bool = false
    ) {
        self.exitCode = exitCode
        self.output = output
        self.responses = responses
        self.throwsOnCapture = throwsOnCapture
    }

    let exitCode: Int32
    let output: String
    let responses: [String: (exitCode: Int32, output: String)]
    let throwsOnCapture: Bool

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 {
        exitCode
    }

    func launchCapturing(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> (exitCode: Int32, output: String) {
        if throwsOnCapture { throw CocoaError(.fileReadNoSuchFile) }
        let key = executableURL.lastPathComponent
        return responses[key] ?? (exitCode: exitCode, output: output)
    }
}

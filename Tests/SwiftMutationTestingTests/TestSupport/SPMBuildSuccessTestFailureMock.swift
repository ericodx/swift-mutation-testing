import Foundation

@testable import SwiftMutationTesting

actor SPMBuildSuccessTestFailureMock: ProcessLaunching {
    private let failureOutput: String
    private let exitCode: Int32

    init(failureOutput: String, exitCode: Int32 = 1) {
        self.failureOutput = failureOutput
        self.exitCode = exitCode
    }

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 { 0 }

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String) {
        request.recordActivation()
        if request.arguments.first == "test" { return (exitCode, failureOutput) }
        return (0, "")
    }
}

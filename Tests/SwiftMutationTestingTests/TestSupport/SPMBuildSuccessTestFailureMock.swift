import Foundation

@testable import SwiftMutationTesting

actor SPMBuildSuccessTestFailureMock: ProcessLaunching {
    private let failureOutput: String

    init(failureOutput: String) {
        self.failureOutput = failureOutput
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
        if request.arguments.first == "test" { return (1, failureOutput) }
        return (0, "")
    }
}

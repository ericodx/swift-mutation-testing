import Foundation

@testable import SwiftMutationTesting

actor SPMPerMutantBuildTimeoutMock: ProcessLaunching {
    private var buildCount = 0

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 {
        0
    }

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String) {
        guard request.arguments.first == "build" else { return (0, "") }

        buildCount += 1
        guard buildCount > 1 else { return (0, "") }

        return (SPMResultParser.timedOutExitCode, "")
    }
}

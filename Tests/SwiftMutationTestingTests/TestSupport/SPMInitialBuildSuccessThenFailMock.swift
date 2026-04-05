import Foundation

@testable import SwiftMutationTesting

actor SPMInitialBuildSuccessThenFailMock: ProcessLaunching {
    private var buildCallCount = 0

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 { 0 }

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String) {
        if request.arguments.contains("--build-tests") || request.arguments.first == "build" {
            buildCallCount += 1
            if buildCallCount == 1 { return (0, "") }
            return (1, "error: build failed")
        }
        return (0, "")
    }
}

import Foundation

@testable import SwiftMutationTesting

actor ThrowingDuringTestMock: ProcessLaunching {
    private var testCallCount = 0

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 { 0 }

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String) {
        if request.arguments.first == "test" {
            testCallCount += 1
            if testCallCount > 1 {
                throw CocoaError(.fileReadNoSuchFile)
            }
        }
        return (0, "")
    }
}

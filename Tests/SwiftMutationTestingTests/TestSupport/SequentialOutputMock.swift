import Foundation

@testable import SwiftMutationTesting

actor SequentialOutputMock: ProcessLaunching {
    private let outputs: [String]
    private var callIndex = 0

    init(outputs: [String]) {
        self.outputs = outputs
    }

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
        let output = outputs[min(callIndex, outputs.count - 1)]
        callIndex += 1
        return (0, output)
    }
}

import Foundation

@testable import SwiftMutationTesting

actor RecordingProcessLauncher: ProcessLaunching {
    private let responses: [(exitCode: Int32, output: String)]
    private var callIndex = 0
    private(set) var requests: [ProcessRequest] = []

    init(responses: [(exitCode: Int32, output: String)]) {
        self.responses = responses
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
        requests.append(request)
        let response = responses[min(callIndex, responses.count - 1)]
        callIndex += 1
        return response
    }

    func recorded(commandStartingWith verb: String) -> ProcessRequest? {
        requests.first { $0.arguments.first == verb }
    }

    func timeouts(forCommandStartingWith verb: String) -> [Double] {
        requests.filter { $0.arguments.first == verb }.map(\.timeout)
    }
}

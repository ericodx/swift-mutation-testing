import Foundation

@testable import SwiftMutationTesting

actor RecordingSPMRetryLauncher: ProcessLaunching {
    private let failingFileName: String
    private var buildCount = 0
    private(set) var requests: [ProcessRequest] = []

    init(failingFileName: String) {
        self.failingFileName = failingFileName
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

        guard request.arguments.first == "build" else { return (0, "") }

        buildCount += 1
        guard buildCount == 1 else { return (0, "") }

        let root = request.workingDirectoryURL.path
        let resolved = root.withCString { pointer -> String in
            guard let real = realpath(pointer, nil) else { return root }
            defer { free(real) }
            return String(cString: real)
        }

        return (1, "\(resolved)/\(failingFileName):1:5: error: cannot convert value")
    }

    func timeouts(forCommandStartingWith verb: String) -> [Double] {
        requests.filter { $0.arguments.first == verb }.map(\.timeout)
    }
}

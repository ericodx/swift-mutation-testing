import Foundation

@testable import SwiftMutationTesting

actor SPMRetryWithFileDeletionMock: ProcessLaunching {
    private var buildCallCount = 0
    private let fileToDelete: String

    init(fileToDelete: String) {
        self.fileToDelete = fileToDelete
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
        guard request.arguments.first == "build" else { return (0, "") }
        buildCallCount += 1
        if buildCallCount == 1 {
            let fooPath = request.workingDirectoryURL.appendingPathComponent("Foo.swift").path
            let canonical = fooPath.withCString { ptr in
                guard let resolved = realpath(ptr, nil) else { return fooPath }
                defer { free(resolved) }
                return String(cString: resolved)
            }
            return (1, "\(canonical):1:5: error: cannot convert value")
        }
        try? FileManager.default.removeItem(atPath: fileToDelete)
        return (0, "")
    }
}

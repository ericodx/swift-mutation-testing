import Foundation

@testable import SwiftMutationTesting

actor SPMErrorWithoutLineNumberMock: ProcessLaunching {
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
        guard request.arguments.first == "build" else { return (0, "") }
        buildCallCount += 1
        if buildCallCount == 1 {
            let fooPath = request.workingDirectoryURL.appendingPathComponent("Foo.swift").path
            let canonical = fooPath.withCString { ptr in
                guard let resolved = realpath(ptr, nil) else { return fooPath }
                defer { free(resolved) }
                return String(cString: resolved)
            }
            return (1, "\(canonical): error: module 'Missing' not found")
        }
        return (0, "")
    }
}

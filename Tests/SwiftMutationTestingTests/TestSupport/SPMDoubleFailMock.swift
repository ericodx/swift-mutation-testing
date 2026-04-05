import Foundation

@testable import SwiftMutationTesting

actor SPMDoubleFailMock: ProcessLaunching {
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

        let root = request.workingDirectoryURL.path
        let resolvedRoot = root.withCString { ptr in
            guard let resolved = realpath(ptr, nil) else { return root }
            defer { free(resolved) }
            return String(cString: resolved)
        }

        if buildCallCount == 1 {
            let fooPath = resolvedRoot + "/Foo.swift"
            return (1, "\(fooPath):1:5: error: cannot convert value")
        }

        if buildCallCount == 2 {
            let barPath = resolvedRoot + "/Bar.swift"
            return (1, "\(barPath):1:5: error: cannot convert value")
        }

        return (0, "")
    }
}

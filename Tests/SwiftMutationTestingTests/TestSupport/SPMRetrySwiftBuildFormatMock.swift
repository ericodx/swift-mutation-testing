import Foundation

@testable import SwiftMutationTesting

actor SPMRetrySwiftBuildFormatMock: ProcessLaunching {
    private let prefix: String
    private var buildCallCount = 0

    init(prefix: String = "error: ") {
        self.prefix = prefix
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
        guard buildCallCount == 1 else { return (0, "") }

        let fooPath = request.workingDirectoryURL.appendingPathComponent("Foo.swift").path
        let canonical = fooPath.withCString { pointer -> String in
            guard let resolved = realpath(pointer, nil) else { return fooPath }
            defer { free(resolved) }
            return String(cString: resolved)
        }
        return (1, "\(prefix)\(canonical):1:5 cannot convert value: FixIt(textToInsert: \" break\")")
    }
}

import Foundation

@testable import SwiftMutationTesting

actor SourceCapturingLauncher: ProcessLaunching {
    private let base: any ProcessLaunching
    private let fileName: String
    private(set) var built: [String] = []

    init(base: any ProcessLaunching, capturing fileName: String) {
        self.base = base
        self.fileName = fileName
    }

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 {
        try await base.launch(
            executableURL: executableURL, arguments: arguments, workingDirectoryURL: workingDirectoryURL,
            timeout: timeout
        )
    }

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String) {
        if Self.isBuild(request),
            let source = try? String(
                contentsOf: request.workingDirectoryURL.appendingPathComponent(fileName), encoding: .utf8
            )
        {
            built.append(source)
        }
        return try await base.launchCapturing(request)
    }

    private static func isBuild(_ request: ProcessRequest) -> Bool {
        switch request.executableURL.lastPathComponent {
        case "xcodebuild": request.arguments.first == "build-for-testing"
        case "swift": request.arguments.first == "build"
        default: false
        }
    }
}

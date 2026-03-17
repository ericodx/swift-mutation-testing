import Foundation

@testable import SwiftMutationTesting

struct MockProcessLauncher: ProcessLaunching {
    let exitCode: Int32
    let output: String

    init(exitCode: Int32, output: String = "") {
        self.exitCode = exitCode
        self.output = output
    }

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 {
        exitCode
    }

    func launchCapturing(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> (exitCode: Int32, output: String) {
        (exitCode: exitCode, output: output)
    }
}

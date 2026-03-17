import Foundation

@testable import SwiftMutationTesting

struct MockProcessLauncher: ProcessLaunching {

    init(exitCode: Int32, output: String = "") {
        self.exitCode = exitCode
        self.output = output
    }

    let exitCode: Int32
    let output: String

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

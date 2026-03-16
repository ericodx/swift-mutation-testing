import Foundation

@testable import SwiftMutationTesting

struct MockProcessLauncher: ProcessLaunching {
    let exitCode: Int32

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
        (exitCode: exitCode, output: "")
    }
}

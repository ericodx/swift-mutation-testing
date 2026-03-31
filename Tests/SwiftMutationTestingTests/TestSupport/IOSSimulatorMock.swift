import Foundation

@testable import SwiftMutationTesting

struct IOSSimulatorMock: ProcessLaunching {
    let listJSON: String
    let cloneUDID: String

    func launch(
        executableURL: URL, arguments: [String], workingDirectoryURL: URL, timeout: Double
    ) async throws -> Int32 {
        1
    }

    func launchCapturing(
        executableURL: URL, arguments: [String], environment: [String: String]?,
        additionalEnvironment: [String: String], workingDirectoryURL: URL, timeout: Double
    ) async throws -> (exitCode: Int32, output: String) {
        if arguments.contains("clone") { return (0, cloneUDID + "\n") }
        return (0, listJSON)
    }
}

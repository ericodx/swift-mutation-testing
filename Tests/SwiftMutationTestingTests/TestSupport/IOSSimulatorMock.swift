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
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String) {
        if request.arguments.contains("clone") { return (0, cloneUDID + "\n") }
        if request.executableURL.lastPathComponent == "xcodebuild" { return (1, "") }
        return (0, listJSON)
    }
}

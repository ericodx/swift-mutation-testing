import Foundation

@testable import SwiftMutationTesting

struct SimulatorCommandMock: ProcessLaunching {
    static func bootedDevicesJSON(udid: String, name: String = "Mock Device") -> String {
        """
        {"devices":{"com.apple.runtime.iOS":[{"udid":"\(udid)","name":"\(name)","state":"Booted"}]}}
        """
    }

    let listOutput: String
    let cloneUDID: String

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 {
        0
    }

    func launchCapturing(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> (exitCode: Int32, output: String) {
        if arguments.contains("clone") {
            return (0, cloneUDID + "\n")
        }

        if arguments.contains("list") {
            return (0, listOutput)
        }

        return (0, "")
    }
}

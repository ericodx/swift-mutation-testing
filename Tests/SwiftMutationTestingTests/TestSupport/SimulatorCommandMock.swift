import Foundation

@testable import SwiftMutationTesting

struct SimulatorCommandMock: ProcessLaunching {

    let listOutput: String
    let cloneUDID: String

    static func bootedDevicesJSON(udid: String, name: String = "Mock Device") -> String {
        """
        {"devices":{"com.apple.runtime.iOS":[{"udid":"\(udid)","name":"\(name)","state":"Booted"}]}}
        """
    }

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 {
        0
    }

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String) {
        if request.arguments.contains("clone") {
            return (0, cloneUDID + "\n")
        }

        if request.arguments.contains("list") {
            return (0, listOutput)
        }

        return (0, "")
    }
}

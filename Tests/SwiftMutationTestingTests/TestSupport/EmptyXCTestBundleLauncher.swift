import Foundation

@testable import SwiftMutationTesting

actor EmptyXCTestBundleLauncher: ProcessLaunching {
    private(set) var xctestRuns = 0
    private(set) var swiftTestingRuns = 0

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
        if request.arguments.first == "build" {
            let macOS = request.workingDirectoryURL
                .appendingPathComponent(".build/out/Products/Debug/PkgTests.xctest/Contents/MacOS")
            try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: macOS.appendingPathComponent("PkgTests").path, contents: Data())
            return (0, "")
        }

        if request.arguments.first == "xctest" {
            xctestRuns += 1
            return (0, "Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds")
        }

        if request.executableURL.lastPathComponent == "swiftpm-testing-helper" {
            swiftTestingRuns += 1
        }

        return (0, "")
    }
}

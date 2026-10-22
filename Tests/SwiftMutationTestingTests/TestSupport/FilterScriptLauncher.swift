import Foundation

@testable import SwiftMutationTesting

actor FilterScriptLauncher: ProcessLaunching {
    static let passing: (exitCode: Int32, output: String) = (
        0, "✔ Test run with 9 tests in 3 suites passed after 0.2 seconds."
    )

    private var outcomes: [String: [(exitCode: Int32, output: String)]]
    private(set) var filters: [String?] = []

    init(outcomes: [String: [(exitCode: Int32, output: String)]]) {
        self.outcomes = outcomes
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
        request.recordActivation()
        if request.arguments.first == "build" {
            let macOS = request.workingDirectoryURL
                .appendingPathComponent(".build/out/Products/Debug/PkgTests.xctest/Contents/MacOS")
            try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: macOS.appendingPathComponent("PkgTests").path, contents: Data())
            return (0, "")
        }

        if request.arguments.first == "xctest" {
            return (TestBundleInvocation.noTestsExitCode, "")
        }

        guard request.executableURL.lastPathComponent == "swiftpm-testing-helper" else { return (0, "") }

        if request.additionalEnvironment["__SWIFT_MUTATION_TESTING_ACTIVE"] == "" { return Self.passing }

        let filter = request.arguments.firstIndex(of: "--filter").map { request.arguments[$0 + 1] }
        filters.append(filter)

        let key = filter ?? ""
        guard let next = outcomes[key]?.first else { return Self.passing }
        outcomes[key]?.removeFirst()
        return next
    }
}

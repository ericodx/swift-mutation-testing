import Foundation

@testable import SwiftMutationTesting

/// Succeeds at everything except the baseline test run, which is given the configured outcome.
///
/// The baseline is the one `swift test` invocation that selects no mutant, which is how it is told
/// apart from a mutant's own run here. `mutantTestRuns` counts the runs that did select one, so a
/// test can assert that a rejected baseline stopped the run before any mutant was tested.
actor SPMBaselineOutcomeMock: ProcessLaunching {

    init(exitCode: Int32, output: String = "") {
        self.exitCode = exitCode
        self.output = output
    }

    private let exitCode: Int32
    private let output: String
    private(set) var mutantTestRuns = 0

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 { 0 }

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String) {
        guard request.arguments.first == "test" else { return (0, "") }

        let selectedMutant = request.additionalEnvironment["__SWIFT_MUTATION_TESTING_ACTIVE"] ?? ""

        guard !selectedMutant.isEmpty else { return (exitCode, output) }

        mutantTestRuns += 1
        return (0, "")
    }
}

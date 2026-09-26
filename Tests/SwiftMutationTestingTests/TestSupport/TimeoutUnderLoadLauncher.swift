import Foundation

@testable import SwiftMutationTesting

actor TimeoutUnderLoadLauncher: ProcessLaunching {
    private let timesOutFirst: Set<String>
    private let alwaysTimesOut: Set<String>
    private var attempts: [String: Int] = [:]
    private var inFlight = 0
    private(set) var sequence: [(id: String, attempt: Int)] = []
    private(set) var inFlightDuringRetry: [String: Int] = [:]
    private(set) var maxInFlightDuringFirstAttempts = 0

    init(timesOutFirst: Set<String>, alwaysTimesOut: Set<String> = []) {
        self.timesOutFirst = timesOutFirst
        self.alwaysTimesOut = alwaysTimesOut
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
        guard let id = request.additionalEnvironment["__SWIFT_MUTATION_TESTING_ACTIVE"] else {
            return (0, "")
        }

        inFlight += 1
        defer { inFlight -= 1 }

        let attempt = (attempts[id] ?? 0) + 1
        attempts[id] = attempt
        sequence.append((id: id, attempt: attempt))
        if attempt > 1 {
            inFlightDuringRetry[id] = inFlight
        } else {
            maxInFlightDuringFirstAttempts = max(maxInFlightDuringFirstAttempts, inFlight)
        }

        try await Task.sleep(for: .milliseconds(20))

        if alwaysTimesOut.contains(id) || (attempt == 1 && timesOutFirst.contains(id)) {
            return (SPMResultParser.timedOutExitCode, "")
        }
        return (0, "")
    }

    func attemptCount(for id: String) -> Int {
        attempts[id] ?? 0
    }
}

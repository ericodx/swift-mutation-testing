import Foundation
import Testing

@testable import SwiftMutationTesting

/// Cleanup after a timed-out run must not reach a later run sharing the same sandbox.
///
/// `IncompatibleMutantExecutor.runSPMShared` tests every incompatible mutant sequentially in one
/// sandbox, and the escalation to SIGKILL fires five seconds after the timeout — by which point the
/// next mutant is usually testing. Cleanup that matched processes by sandbox name killed that
/// mutant's test binary, and the truncated output was read as a crash (issue #69).
@Suite("SPM timeout cleanup")
struct SPMTimeoutCleanupTests {

    @Test("Given a timed-out run, when its cleanup fires, then a later run in the same sandbox survives")
    func timedOutRunDoesNotKillLaterRunInSameSandbox() async throws {
        let sandbox = try makeSandboxDirectory()
        defer { FileHelpers.cleanup(sandbox) }

        let launcher = SPMProcessLauncher()

        // The run that times out: killed after 1s, with SIGKILL escalation 5s later.
        async let timedOut = launcher.launchCapturing(
            try request(sleeping: 30, in: sandbox, timeout: 1)
        )

        // The next mutant's run, started in the same sandbox while that escalation is pending.
        try await Task.sleep(for: .milliseconds(1500))
        async let survivor = launcher.launchCapturing(
            try request(sleeping: 8, in: sandbox, timeout: 30)
        )

        let timedOutResult = try await timedOut
        let survivorResult = try await survivor

        #expect(timedOutResult.exitCode == -1, "the first run should be reported as a timeout")
        #expect(
            survivorResult.exitCode == 0,
            "the later run in the same sandbox was killed by the first run's cleanup"
        )
    }

    @Test("Given a timed-out run, when its cleanup fires, then its own descendants are killed")
    func timedOutRunKillsItsOwnDescendants() async throws {
        let sandbox = try makeSandboxDirectory()
        defer { FileHelpers.cleanup(sandbox) }

        let marker = sandbox.appendingPathComponent("child.pid")
        let spawnChild = "sh -c 'echo $$ > \(marker.path); exec sleep 60' & wait"

        let process = ProcessRequest(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", spawnChild],
            environment: nil,
            additionalEnvironment: [:],
            workingDirectoryURL: sandbox,
            timeout: 1
        )

        _ = try await SPMProcessLauncher().launchCapturing(process)

        let childPID = try #require(
            Int32(
                (try String(contentsOf: marker, encoding: .utf8)).trimmingCharacters(in: .whitespacesAndNewlines)
            ))

        // The escalation runs five seconds after the timeout.
        try await Task.sleep(for: .seconds(6))

        #expect(kill(childPID, 0) != 0, "the spawned child outlived the run that started it")
    }

    // MARK: - Private

    private func makeSandboxDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xmr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A run whose arguments name a path inside the sandbox, the way SwiftPM's test bundle does:
    /// it lives at `<sandbox>/.build/...`, so the sandbox name is in its argv. That is what cleanup
    /// used to match on, and why it reached runs that were not its own.
    private func request(sleeping seconds: Int, in sandbox: URL, timeout: Double) throws -> ProcessRequest {
        let script = sandbox.appendingPathComponent("run-\(UUID().uuidString.prefix(8)).sh")
        try "#!/bin/sh\nsleep \(seconds)\n".write(to: script, atomically: true, encoding: .utf8)

        return ProcessRequest(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [script.path],
            environment: nil,
            additionalEnvironment: [:],
            workingDirectoryURL: sandbox,
            timeout: timeout
        )
    }
}

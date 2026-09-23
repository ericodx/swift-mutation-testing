import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("SPM timeout cleanup")
struct SPMTimeoutCleanupTests {

    @Test("Given a timed-out run, when its cleanup fires, then a later run in the same sandbox survives")
    func timedOutRunDoesNotKillLaterRunInSameSandbox() async throws {
        let sandbox = try makeSandboxDirectory()
        defer { FileHelpers.cleanup(sandbox) }

        let launcher = SPMProcessLauncher()

        async let timedOut = launcher.launchCapturing(
            try request(sleeping: 30, in: sandbox, timeout: 1)
        )

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

        try await Task.sleep(for: .milliseconds(500))

        #expect(kill(childPID, 0) != 0, "the spawned child outlived the run that started it")
    }

    // MARK: - Private

    private func makeSandboxDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xmr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

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

import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("TimeoutEscalation")
struct TimeoutEscalationTests {

    @Test("Given an armed escalation, when the process terminates, then descendants die without waiting")
    func killsDescendantsImmediatelyOnTermination() async throws {
        let target = try spawnGroupLeader()
        defer { kill(target, SIGKILL) }
        let child = try spawnSleeper()
        defer { kill(child, SIGKILL) }

        let escalation = TimeoutEscalation(gracePeriod: 30)
        escalation.arm(pid: target, descendants: [child])

        escalation.processTerminated()
        try await Task.sleep(for: .milliseconds(300))

        #expect(kill(child, 0) != 0, "the descendant should not have outlived the run")
    }

    @Test("Given the grace period elapses, when the process is still alive, then descendants are killed")
    func killsDescendantsWhenGracePeriodElapses() async throws {
        let target = try spawnGroupLeader()
        defer { kill(target, SIGKILL) }
        let child = try spawnSleeper()
        defer { kill(child, SIGKILL) }

        let escalation = TimeoutEscalation(gracePeriod: 0.2)
        escalation.arm(pid: target, descendants: [child])

        try await Task.sleep(for: .milliseconds(600))

        #expect(kill(child, 0) != 0, "the descendant should have been killed once the grace period ran out")
        #expect(kill(target, 0) != 0, "the process group should have been killed too")
    }

    @Test("Given termination before the grace period, when it would have elapsed, then nothing is signalled again")
    func doesNotSignalAfterTermination() async throws {
        let target = try spawnGroupLeader()
        defer { kill(target, SIGKILL) }
        let child = try spawnSleeper()
        defer { kill(child, SIGKILL) }

        let escalation = TimeoutEscalation(gracePeriod: 0.3)
        escalation.arm(pid: target, descendants: [child])
        escalation.processTerminated()

        // Started after termination, so the cancelled escalation must not reach it.
        let later = try spawnSleeper()
        defer { kill(later, SIGKILL) }

        try await Task.sleep(for: .milliseconds(600))

        #expect(kill(later, 0) == 0, "a process started after termination must not be reached")
        #expect(kill(target, 0) == 0, "the group must not be killed once the process has terminated")
    }

    @Test("Given no descendants, when the process terminates, then nothing happens")
    func handlesEmptySnapshot() throws {
        let target = try spawnGroupLeader()
        defer { kill(target, SIGKILL) }

        let escalation = TimeoutEscalation(gracePeriod: 0.1)
        escalation.arm(pid: target, descendants: [])

        escalation.processTerminated()

        #expect(kill(target, 0) == 0)
    }

    // MARK: - Private

    /// A throwaway process that leads its own process group, so signalling that group cannot reach
    /// the test runner.
    private func spawnGroupLeader() throws -> Int32 {
        let pid = try spawnSleeper()
        setpgid(pid, pid)

        try #require(
            getpgid(pid) == pid,
            "refusing to signal a group the test runner belongs to"
        )

        return pid
    }

    private func spawnSleeper() throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process.processIdentifier
    }
}

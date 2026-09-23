import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("ProcessTree")
struct ProcessTreeTests {

    @Test("Given a process that spawned a child, when descendants queried, then the child is found")
    func findsDirectChild() async throws {
        let parent = try longRunningShell(spawning: "sleep 30")
        defer { terminate(parent) }

        try await settle()

        let descendants = ProcessTree.descendants(of: parent.processIdentifier)

        #expect(!descendants.isEmpty, "expected at least the spawned sleep")
    }

    @Test("Given a grandchild, when descendants queried, then the whole tree is found")
    func findsGrandchild() async throws {
        let parent = try longRunningShell(spawning: "/bin/sh -c 'sleep 30 & wait'")
        defer { terminate(parent) }

        try await settle()

        let descendants = ProcessTree.descendants(of: parent.processIdentifier)

        #expect(descendants.count >= 2, "expected the child shell and its sleep, got \(descendants)")
    }

    @Test("Given an unrelated process, when descendants queried, then it is not included")
    func excludesUnrelatedProcesses() async throws {
        let parent = try longRunningShell(spawning: "sleep 30")
        defer { terminate(parent) }
        let stranger = try longRunningShell(spawning: "sleep 30")
        defer { terminate(stranger) }

        try await settle()

        let descendants = ProcessTree.descendants(of: parent.processIdentifier)

        #expect(!descendants.contains(stranger.processIdentifier))
    }

    @Test("Given a process with no children, when descendants queried, then the result is empty")
    func returnsEmptyForLeafProcess() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        defer { terminate(process) }

        try await settle()

        #expect(ProcessTree.descendants(of: process.processIdentifier).isEmpty)
    }

    @Test("Given pid 1 or below, when descendants queried, then nothing is returned")
    func refusesToWalkFromInit() {
        #expect(ProcessTree.descendants(of: 1).isEmpty)
        #expect(ProcessTree.descendants(of: 0).isEmpty)
        #expect(ProcessTree.descendants(of: -1).isEmpty)
    }

    // MARK: - Private

    private func longRunningShell(spawning command: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "\(command) & wait"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(300))
    }

    private func terminate(_ process: Process) {
        for descendant in ProcessTree.descendants(of: process.processIdentifier) {
            kill(descendant, SIGKILL)
        }
        if process.isRunning { process.terminate() }
    }
}

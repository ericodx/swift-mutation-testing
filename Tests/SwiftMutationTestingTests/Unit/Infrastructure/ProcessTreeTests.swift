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

    @Test("Given a running process, when all processes are listed, then it is among them")
    func allIncludesARunningProcess() async throws {
        let process = try longRunningShell(spawning: "sleep 30")
        defer { terminate(process) }

        try await settle()

        let all = ProcessTree.all()

        #expect(all.contains(process.processIdentifier))
        #expect(!all.contains(1))
    }

    @Test("Given the process table cannot be read, when all processes are listed, then there are none")
    func allIsEmptyWhenTheTableCannotBeRead() {
        let failing: SystemCalls.Sysctl = { _, _, _, _, _, _ in -1 }

        #expect(ProcessTree.all(sysctl: failing).isEmpty)
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

    @Test("Given the process table cannot be sized, when descendants are asked for, then there are none")
    func aTableThatCannotBeSizedHasNoDescendants() {
        let failing: SystemCalls.Sysctl = { _, _, _, _, _, _ in -1 }

        #expect(ProcessTree.descendants(of: 2, sysctl: failing).isEmpty)
    }

    @Test("Given the process table cannot be read after sizing, when descendants are asked for, then there are none")
    func aTableThatCannotBeReadHasNoDescendants() {
        var calls = 0
        let failingOnRead: SystemCalls.Sysctl = { _, _, _, size, _, _ in
            calls += 1
            guard calls == 1 else {
                errno = EPERM
                return -1
            }
            size?.pointee = MemoryLayout<kinfo_proc>.stride * 4
            return 0
        }

        #expect(ProcessTree.descendants(of: 2, sysctl: failingOnRead).isEmpty)
        #expect(calls == 2)
    }

    @Test("Given the table grows between sizing and reading, when descendants are asked for, then they are found")
    func aTableThatGrowsIsReadAgain() {
        var reads = 0
        let growing: SystemCalls.Sysctl = { _, _, buffer, size, _, _ in
            let stride = MemoryLayout<kinfo_proc>.stride
            guard let buffer else {
                size?.pointee = stride * 2
                return 0
            }
            reads += 1
            guard reads > 1 else {
                errno = ENOMEM
                return -1
            }
            let procs = buffer.bindMemory(to: kinfo_proc.self, capacity: 2)
            procs[0].kp_proc.p_pid = 10
            procs[0].kp_eproc.e_ppid = 2
            procs[1].kp_proc.p_pid = 11
            procs[1].kp_eproc.e_ppid = 10
            size?.pointee = stride * 2
            return 0
        }

        #expect(ProcessTree.descendants(of: 2, sysctl: growing) == [10, 11])
        #expect(reads == 2)
    }

    @Test("Given the process table keeps outgrowing the buffer, when descendants are asked for, then reading gives up")
    func aTableThatKeepsGrowingGivesUp() {
        var reads = 0
        let alwaysGrowing: SystemCalls.Sysctl = { _, _, buffer, size, _, _ in
            guard buffer != nil else {
                size?.pointee = MemoryLayout<kinfo_proc>.stride * 2
                return 0
            }
            reads += 1
            errno = ENOMEM
            return -1
        }

        #expect(ProcessTree.descendants(of: 2, sysctl: alwaysGrowing).isEmpty)
        #expect(reads == 3)
    }

    @Test("Given this process and one that has exited, when asked whether they are alive, then only this one is")
    func liveAndExitedProcessesAreTold() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()

        #expect(ProcessTree.isAlive(getpid()))
        #expect(!ProcessTree.isAlive(process.processIdentifier))
    }
}

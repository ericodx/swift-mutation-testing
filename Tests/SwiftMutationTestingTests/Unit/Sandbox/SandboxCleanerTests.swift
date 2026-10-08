import Foundation
import Synchronization
import Testing

@testable import SwiftMutationTesting

@Suite("SandboxCleaner")
struct SandboxCleanerTests {

    @Test("Given orphaned xmr directories, when removeOrphaned called, then all are deleted")
    func removeOrphanedDeletesXmrDirectories() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let orphan1 = baseDir.appendingPathComponent("xmr-\(UUID().uuidString)")
        let orphan2 = baseDir.appendingPathComponent("xmr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: orphan1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: orphan2, withIntermediateDirectories: true)
        try "content".write(
            to: orphan1.appendingPathComponent("file.swift"),
            atomically: true, encoding: .utf8
        )

        SandboxCleaner.removeOrphaned(in: baseDir)

        #expect(!FileManager.default.fileExists(atPath: orphan1.path))
        #expect(!FileManager.default.fileExists(atPath: orphan2.path))
    }

    @Test("Given a sandbox owned by a live process, when removeOrphaned called, then it is preserved")
    func removeOrphanedPreservesSandboxOfLiveOwner() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let live = baseDir.appendingPathComponent(SandboxName.make())
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        try "content".write(
            to: live.appendingPathComponent("file.swift"),
            atomically: true, encoding: .utf8
        )

        SandboxCleaner.removeOrphaned(in: baseDir)

        #expect(FileManager.default.fileExists(atPath: live.path))
    }

    @Test("Given a sandbox whose owner has exited, when removeOrphaned called, then it is deleted")
    func removeOrphanedDeletesSandboxOfExitedOwner() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()

        let abandoned = baseDir.appendingPathComponent(SandboxName.make(pid: process.processIdentifier))
        try FileManager.default.createDirectory(at: abandoned, withIntermediateDirectories: true)

        SandboxCleaner.removeOrphaned(in: baseDir)

        #expect(!FileManager.default.fileExists(atPath: abandoned.path))
    }

    @Test("Given no directory, when removeOrphaned called, then it sweeps the sandbox directory")
    func removeOrphanedDefaultsToSandboxDirectory() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()

        let abandoned = SandboxName.directory.appendingPathComponent(SandboxName.make(pid: process.processIdentifier))
        try FileManager.default.createDirectory(at: abandoned, withIntermediateDirectories: true)
        defer { FileHelpers.cleanup(abandoned) }

        SandboxCleaner.removeOrphaned()

        #expect(!FileManager.default.fileExists(atPath: abandoned.path))
    }

    @Test("Given a sandbox this process created, when another run sweeps, then the sandbox survives")
    func sweepFromAnotherRunSparesASandboxInUse() async throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }
        try "let x = 1".write(
            to: projectDir.appendingPathComponent("Main.swift"),
            atomically: true, encoding: .utf8
        )

        let sandbox = try await SandboxFactory().createClean(projectPath: projectDir.path)
        defer { FileHelpers.cleanup(sandbox.rootURL) }

        let asAnotherRunSeesIt = baseDir.appendingPathComponent(sandbox.rootURL.lastPathComponent)
        try FileManager.default.copyItem(at: sandbox.rootURL, to: asAnotherRunSeesIt)

        SandboxCleaner.removeOrphaned(in: baseDir)

        #expect(FileManager.default.fileExists(atPath: asAnotherRunSeesIt.path))
    }

    @Test("Given non-xmr directories, when removeOrphaned called, then they are preserved")
    func removeOrphanedPreservesNonXmrDirectories() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let unrelated = baseDir.appendingPathComponent("other-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)

        SandboxCleaner.removeOrphaned(in: baseDir)

        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }

    @Test("Given orphaned xmr directories with nested content, when removeOrphaned called, then entire tree is removed")
    func removeOrphanedDeletesNestedContent() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let orphan = baseDir.appendingPathComponent("xmr-\(UUID().uuidString)")
        let nestedDir = orphan.appendingPathComponent("Sources/MyLib")
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        try "nested".write(
            to: nestedDir.appendingPathComponent("File.swift"),
            atomically: true, encoding: .utf8
        )

        SandboxCleaner.removeOrphaned(in: baseDir)

        #expect(!FileManager.default.fileExists(atPath: orphan.path))
    }

    @Test("Given empty directory, when removeOrphaned called, then no error occurs")
    func removeOrphanedOnEmptyDirectoryIsNoOp() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        SandboxCleaner.removeOrphaned(in: baseDir)
    }

    @Test("Given mixed xmr and non-xmr entries, when removeOrphaned called, then only xmr are removed")
    func removeOrphanedDeletesOnlyXmrEntries() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let xmrDir = baseDir.appendingPathComponent("xmr-\(UUID().uuidString)")
        let otherDir = baseDir.appendingPathComponent("something-else")
        let regularFile = baseDir.appendingPathComponent("file.txt")
        try FileManager.default.createDirectory(at: xmrDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)
        try "data".write(to: regularFile, atomically: true, encoding: .utf8)

        SandboxCleaner.removeOrphaned(in: baseDir)

        #expect(!FileManager.default.fileExists(atPath: xmrDir.path))
        #expect(FileManager.default.fileExists(atPath: otherDir.path))
        #expect(FileManager.default.fileExists(atPath: regularFile.path))
    }

    @Test("Given no active sandbox, when deregister called, then no error occurs")
    func deregisterWithoutRegisterIsNoOp() {
        SandboxCleaner.deregister(in: SandboxRegistry())
    }

    @Test("Given registered sandbox, when cleanupActiveSandbox called, then sandbox directory is removed")
    func cleanupActiveSandboxRemovesRegisteredDirectory() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        let sandboxDir = baseDir.appendingPathComponent("xmr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandboxDir, withIntermediateDirectories: true)
        try "content".write(
            to: sandboxDir.appendingPathComponent("file.swift"),
            atomically: true, encoding: .utf8
        )

        let registry = SandboxRegistry()
        SandboxCleaner.register(Sandbox(rootURL: sandboxDir), in: registry)
        SandboxCleaner.cleanupActiveSandbox(in: registry)

        #expect(!FileManager.default.fileExists(atPath: sandboxDir.path))
        FileHelpers.cleanup(baseDir)
    }

    @Test("Given no registered sandbox, when cleanupActiveSandbox called, then no error occurs")
    func cleanupActiveSandboxWithoutRegistrationIsNoOp() {
        SandboxCleaner.cleanupActiveSandbox(in: SandboxRegistry())
    }

    @Test("Given registered sandbox, when deregister called, then cleanupActiveSandbox does not remove directory")
    func deregisterPreventsCleanup() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let sandboxDir = baseDir.appendingPathComponent("xmr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandboxDir, withIntermediateDirectories: true)

        let registry = SandboxRegistry()
        SandboxCleaner.register(Sandbox(rootURL: sandboxDir), in: registry)
        SandboxCleaner.deregister(in: registry)
        SandboxCleaner.cleanupActiveSandbox(in: registry)

        #expect(FileManager.default.fileExists(atPath: sandboxDir.path))
    }

    @Test("Given registered sandbox, when register called again, then new sandbox is tracked")
    func registerOverwritesPreviousRegistration() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let first = baseDir.appendingPathComponent("xmr-first")
        let second = baseDir.appendingPathComponent("xmr-second")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        let registry = SandboxRegistry()
        SandboxCleaner.register(Sandbox(rootURL: first), in: registry)
        SandboxCleaner.register(Sandbox(rootURL: second), in: registry)
        SandboxCleaner.cleanupActiveSandbox(in: registry)

        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(!FileManager.default.fileExists(atPath: second.path))
    }

    @Test("Given registered sandbox, when terminated, then sandbox is removed and the exit code is 1")
    func terminateCleansSandboxAndExits() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let sandboxDir = baseDir.appendingPathComponent("xmr-signal-test")
        try FileManager.default.createDirectory(at: sandboxDir, withIntermediateDirectories: true)
        try "content".write(
            to: sandboxDir.appendingPathComponent("file.swift"),
            atomically: true, encoding: .utf8
        )

        let registry = SandboxRegistry()
        SandboxCleaner.register(Sandbox(rootURL: sandboxDir), in: registry)

        var exitCode: Int32?
        SandboxCleaner.terminate(registry: registry, processGroups: ProcessGroupRegistry()) { exitCode = $0 }

        #expect(!FileManager.default.fileExists(atPath: sandboxDir.path))
        #expect(exitCode == 1)
    }

    @Test("Given no registered sandbox, when terminated, then the exit code is still 1")
    func terminateWithNoSandboxStillExits() {
        var exitCode: Int32?
        SandboxCleaner.terminate(registry: SandboxRegistry(), processGroups: ProcessGroupRegistry()) { exitCode = $0 }

        #expect(exitCode == 1)
    }

    @Test("Given a test run in flight, when terminated, then its process group is killed before the exit")
    func terminateKillsTrackedProcessGroups() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        defer { if process.isRunning { process.terminate() } }

        let processGroups = ProcessGroupRegistry()
        processGroups.register(process.processIdentifier)

        var exitCode: Int32?
        SandboxCleaner.terminate(registry: SandboxRegistry(), processGroups: processGroups) { exitCode = $0 }

        let deadline = ContinuousClock.now + .seconds(5)
        while process.isRunning, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(!process.isRunning, "the tracked test process outlived the tool")
        #expect(process.terminationReason == .uncaughtSignal)
        #expect(exitCode == 1)
    }

    @Test("Given signal handlers installed, when a handled signal arrives, then the sandbox goes and it exits with 1")
    func installedHandlerCleansSandboxAndExits() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let sandboxDir = baseDir.appendingPathComponent("xmr-signal-test")
        try FileManager.default.createDirectory(at: sandboxDir, withIntermediateDirectories: true)

        let registry = SandboxRegistry()
        registry.register(Sandbox(rootURL: sandboxDir))
        let recorder = ExitRecorder()

        SandboxCleaner.installSignalHandlers()
        SandboxCleaner.installSignalHandlers()
        let interrupt = signal(SIGINT, SIG_DFL)
        let terminate = signal(SIGTERM, SIG_DFL)
        let hangUp = signal(SIGHUP, SIG_DFL)

        let address = { (handler: sig_t?) in unsafeBitCast(handler, to: Int.self) }
        #expect(address(interrupt) != address(SIG_DFL))
        #expect(address(interrupt) != address(SIG_IGN))
        #expect(address(terminate) == address(interrupt))
        #expect(address(hangUp) == address(interrupt))

        let handler = try #require(interrupt)
        signal(SIGINT, handler)
        defer { signal(SIGINT, SIG_DFL) }
        SandboxCleaner.withSignalTarget(
            .init(registry: registry, processGroups: ProcessGroupRegistry(), exit: recorder.record)
        ) {
            handler(SIGINT)
            #expect(FileManager.default.fileExists(atPath: sandboxDir.path), "the C handler must not clean up itself")
            #expect(recorder.code == nil)

            kill(getpid(), SIGINT)
            let deadline = ContinuousClock.now + .seconds(5)
            while recorder.code == nil, ContinuousClock.now < deadline {
                usleep(10_000)
            }
        }

        #expect(!FileManager.default.fileExists(atPath: sandboxDir.path))
        #expect(recorder.code == 1)
    }

    @Test("Given a directory that cannot be listed, when removeOrphaned called, then it returns without complaint")
    func aDirectoryThatCannotBeListedIsLeftAlone() {
        SandboxCleaner.removeOrphaned(in: URL(fileURLWithPath: "/does/not/exist/\(UUID().uuidString)"))
    }
}

private final class ExitRecorder: Sendable {

    var code: Int32? {
        recorded.withLock { $0 }
    }

    func record(_ code: Int32) {
        recorded.withLock { $0 = code }
    }

    // MARK: - Private

    private let recorded = Mutex<Int32?>(nil)
}

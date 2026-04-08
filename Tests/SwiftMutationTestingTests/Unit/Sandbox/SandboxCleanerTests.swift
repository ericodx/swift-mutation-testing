import Foundation
import Testing

@testable import SwiftMutationTesting

nonisolated(unsafe) private var capturedExitCode: Int32?

private func stubExitHandler(_ code: Int32) {
    capturedExitCode = code
}

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
        SandboxCleaner.deregister()
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

        let sandbox = Sandbox(rootURL: sandboxDir)
        SandboxCleaner.register(sandbox)
        SandboxCleaner.cleanupActiveSandbox()

        #expect(!FileManager.default.fileExists(atPath: sandboxDir.path))
        FileHelpers.cleanup(baseDir)
    }

    @Test("Given no registered sandbox, when cleanupActiveSandbox called, then no error occurs")
    func cleanupActiveSandboxWithoutRegistrationIsNoOp() {
        SandboxCleaner.deregister()
        SandboxCleaner.cleanupActiveSandbox()
    }

    @Test("Given registered sandbox, when deregister called, then cleanupActiveSandbox does not remove directory")
    func deregisterPreventsCleanup() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let sandboxDir = baseDir.appendingPathComponent("xmr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandboxDir, withIntermediateDirectories: true)

        let sandbox = Sandbox(rootURL: sandboxDir)
        SandboxCleaner.register(sandbox)
        SandboxCleaner.deregister()
        SandboxCleaner.cleanupActiveSandbox()

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

        SandboxCleaner.register(Sandbox(rootURL: first))
        SandboxCleaner.register(Sandbox(rootURL: second))
        SandboxCleaner.cleanupActiveSandbox()

        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(!FileManager.default.fileExists(atPath: second.path))
    }

    @Test("Given registered sandbox, when handleSignal fires, then sandbox is removed and exit handler called with 1")
    func handleSignalCleansSandboxAndExits() throws {
        let baseDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(baseDir) }

        let sandboxDir = baseDir.appendingPathComponent("xmr-signal-test")
        try FileManager.default.createDirectory(at: sandboxDir, withIntermediateDirectories: true)
        try "content".write(
            to: sandboxDir.appendingPathComponent("file.swift"),
            atomically: true, encoding: .utf8
        )

        SandboxCleaner.register(Sandbox(rootURL: sandboxDir))
        SandboxCleaner.installSignalHandlers()
        defer {
            signal(SIGINT, SIG_DFL)
            signal(SIGTERM, SIG_DFL)
            SandboxCleaner.deregister()
        }

        let handler = signal(SIGINT, SIG_DFL)!
        signal(SIGINT, handler)

        let previousExit = sandboxCleanerExitHandler
        capturedExitCode = nil
        sandboxCleanerExitHandler = stubExitHandler
        defer { sandboxCleanerExitHandler = previousExit }

        handler(SIGINT)

        #expect(!FileManager.default.fileExists(atPath: sandboxDir.path))
        #expect(capturedExitCode == 1)
    }

    @Test("Given no registered sandbox, when handleSignal fires, then exit handler called with 1")
    func handleSignalWithNoSandboxStillExits() {
        SandboxCleaner.deregister()
        SandboxCleaner.installSignalHandlers()
        defer {
            signal(SIGINT, SIG_DFL)
            signal(SIGTERM, SIG_DFL)
        }

        let handler = signal(SIGINT, SIG_DFL)!
        signal(SIGINT, handler)

        let previousExit = sandboxCleanerExitHandler
        capturedExitCode = nil
        sandboxCleanerExitHandler = stubExitHandler
        defer { sandboxCleanerExitHandler = previousExit }

        handler(SIGINT)

        #expect(capturedExitCode == 1)
    }
}

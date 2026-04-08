import Foundation
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
}

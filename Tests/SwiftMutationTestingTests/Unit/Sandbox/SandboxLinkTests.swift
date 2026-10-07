import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("SandboxLink")
struct SandboxLinkTests {
    @Test("Given a mutated file in the sandbox, when its link is restored, then it points at the original again")
    func restoringReplacesTheMutatedFileWithALink() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let original = dir.appendingPathComponent("Calc.swift").path
        let copy = dir.appendingPathComponent("Sandboxed.swift").path
        try "let a = 1".write(toFile: original, atomically: true, encoding: .utf8)
        try "let a = 2".write(toFile: copy, atomically: true, encoding: .utf8)

        try SandboxLink.restore(at: copy, to: original)

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: copy) == original)
    }

    @Test("Given a sandbox directory that cannot be written, when the link is restored, then it throws")
    func aLinkThatCannotBeRestoredStopsTheRun() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        let locked = dir.appendingPathComponent("Locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let copy = locked.appendingPathComponent("Calc.swift").path
        try "let a = 2".write(toFile: copy, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            FileHelpers.cleanup(dir)
        }

        #expect(throws: IntegrityError.sourceNotRestored(path: "/p/Calc.swift")) {
            try SandboxLink.restore(at: copy, to: "/p/Calc.swift")
        }
    }
}

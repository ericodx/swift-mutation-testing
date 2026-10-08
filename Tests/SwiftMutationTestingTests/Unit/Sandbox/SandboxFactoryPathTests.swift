import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("SandboxFactory — matching replaced files")
struct SandboxFactoryPathTests {
    private let factory = SandboxFactory()

    @Test("Given a project reached through a symlink, when a nested file is schematized, then the sandbox holds it")
    func aSymlinkedRootStillMatchesANestedFile() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let real = dir.appendingPathComponent("real")
        let link = dir.appendingPathComponent("link")
        let sources = real.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        try FileHelpers.write("let a = 1", named: "A.swift", in: sources)
        try FileHelpers.write("let b = 1", named: "B.swift", in: sources)

        let sandbox = try await factory.create(
            projectPath: link.path,
            schematizedFiles: [
                SchematizedFile(
                    originalPath: link.appendingPathComponent("Sources/App/A.swift").path,
                    schematizedContent: "let a = 2"
                )
            ]
        )
        defer { try? sandbox.cleanup() }

        let copy = sandbox.rootURL.appendingPathComponent("Sources/App")
        #expect(try String(contentsOf: copy.appendingPathComponent("A.swift"), encoding: .utf8) == "let a = 2")
        #expect(
            try FileManager.default.destinationOfSymbolicLink(atPath: copy.appendingPathComponent("B.swift").path)
                .hasSuffix("/Sources/App/B.swift")
        )
    }

    @Test("Given a project file that links to a file outside, when that file is mutated, then the copy is replaced")
    func aLinkedFileIsMatchedByItsTarget() async throws {
        let project = try FileHelpers.makeTemporaryDirectory()
        let elsewhere = try FileHelpers.makeTemporaryDirectory()
        defer {
            FileHelpers.cleanup(project)
            FileHelpers.cleanup(elsewhere)
        }
        let target = elsewhere.appendingPathComponent("Shared.swift")
        try "let s = 1".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: project.appendingPathComponent("Shared.swift"), withDestinationURL: target
        )

        let sandbox = try await factory.create(
            projectPath: project.path, mutatedFilePath: target.path, mutatedContent: "let s = 2"
        )
        defer { try? sandbox.cleanup() }

        let copy = sandbox.rootURL.appendingPathComponent("Shared.swift")
        #expect(try String(contentsOf: copy, encoding: .utf8) == "let s = 2")
    }

    @Test("Given the file system root, when replaced files are keyed, then their paths are relative to it")
    func replacementsUnderTheRootAreRelative() {
        let replacements = SandboxFactory.Replacements(["/Sources/A.swift": "a"], under: "/")

        #expect(replacements.byRelativePath == ["Sources/A.swift": "a"])
    }

    @Test("Given a directory it cannot list, when projects are looked for, then the others are still searched")
    func anUnreadableDirectoryIsSkipped() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        let locked = dir.appendingPathComponent("Locked")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("App.xcodeproj"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            FileHelpers.cleanup(dir)
        }

        #expect(SandboxFactory.xcodeprojs(in: dir).map(\.lastPathComponent) == ["App.xcodeproj"])
    }

    @Test("Given work off the cooperative pool, when it returns or throws, then the caller gets the same")
    func workOffThePoolReturnsAndThrows() async throws {
        struct Failure: Error {}

        #expect(try await SandboxFactory.offCooperativePool { 42 } == 42)
        await #expect(throws: Failure.self) {
            try await SandboxFactory.offCooperativePool { throw Failure() }
        }
    }
}

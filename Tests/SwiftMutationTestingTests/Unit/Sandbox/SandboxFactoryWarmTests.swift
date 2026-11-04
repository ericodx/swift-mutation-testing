import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("SandboxFactory — warm sandboxes")
struct SandboxFactoryWarmTests {

    @Test("Given a warm factory, when a sandbox is released and made again, then it is the same directory and build")
    func reusesTheSlotAndKeepsTheBuild() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let (project, factory) = try makeProject(in: dir)

        let first = try await factory.createClean(projectPath: project.path)
        #expect(first.isPersistent)
        #expect(first.rootURL.lastPathComponent == WarmSandboxes.name(for: project.path, slot: 0))
        for path in [".build/debug/App.o", ".xmr-derived-data/Build/x"] {
            let url = first.rootURL.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try "built".write(to: url, atomically: true, encoding: .utf8)
        }
        try first.cleanup()
        #expect(FileManager.default.fileExists(atPath: first.rootURL.path))

        let second = try await factory.createClean(projectPath: project.path)
        defer { try? second.cleanup() }

        #expect(second.rootURL.path == first.rootURL.path)
        let kept = second.rootURL
        #expect(FileManager.default.fileExists(atPath: kept.appendingPathComponent(".build/debug/App.o").path))
        #expect(FileManager.default.fileExists(atPath: kept.appendingPathComponent(".xmr-derived-data/Build/x").path))
        #expect(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: second.rootURL.appendingPathComponent("Sources/App/A.swift").path
            ).hasSuffix("/Sources/App/A.swift")
        )
    }

    @Test("Given a slot that cannot be pruned, when a sandbox is made, then it throws and the slot is free again")
    func aFailedPruneReleasesTheSlot() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        let (project, factory) = try makeProject(in: dir)
        let first = try await factory.createClean(projectPath: project.path)
        try first.cleanup()
        let locked = first.rootURL.appendingPathComponent("Stale")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileHelpers.write("stale", named: "inner.txt", in: locked)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            FileHelpers.cleanup(dir)
        }

        await #expect(throws: (any Error).self) { try await factory.createClean(projectPath: project.path) }

        let (url, slot) = try #require(factory.warm).claim(projectPath: project.path)
        defer { slot.unlock() }
        #expect(slot.index == 0)
        #expect(url.path == first.rootURL.path)
    }

    @Test(
        "Given a project folder that cannot be read, when a sandbox is made, then it throws and the slot is free again")
    func aFailedPopulateReleasesTheSlot() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        let (project, factory) = try makeProject(in: dir)
        let unreadable = project.appendingPathComponent("Sources/Locked")
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: unreadable.path)
            FileHelpers.cleanup(dir)
        }

        await #expect(throws: (any Error).self) { try await factory.createClean(projectPath: project.path) }

        let (_, slot) = try #require(factory.warm).claim(projectPath: project.path)
        defer { slot.unlock() }
        #expect(slot.index == 0)
    }

    @Test("Given a sandbox of an earlier run, when refreshed, then deleted files go and mutated copies are links again")
    func refreshFollowsTheProject() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let (project, factory) = try makeProject(in: dir)

        let first = try await factory.createClean(projectPath: project.path)
        let sources = first.rootURL.appendingPathComponent("Sources/App")
        try FileManager.default.removeItem(at: sources.appendingPathComponent("A.swift"))
        try "mutated".write(to: sources.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
        try "stale".write(to: sources.appendingPathComponent("Stale.swift"), atomically: true, encoding: .utf8)
        try first.cleanup()
        try FileManager.default.removeItem(at: project.appendingPathComponent("Sources/App/B.swift"))
        try FileHelpers.write("let c = 1", named: "C.swift", in: project.appendingPathComponent("Sources/App"))

        let second = try await factory.createClean(projectPath: project.path)
        defer { try? second.cleanup() }

        let names = try FileManager.default.contentsOfDirectory(atPath: sources.path).sorted()
        #expect(names == ["A.swift", "C.swift"])
        #expect(
            try FileManager.default.destinationOfSymbolicLink(atPath: sources.appendingPathComponent("A.swift").path)
                .hasSuffix("/Sources/App/A.swift")
        )
    }

    @Test("Given an unchanged schematized file, when refreshed, then it keeps its date; a changed one is rewritten")
    func keepsAnUnchangedSchema() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let (project, factory) = try makeProject(in: dir)
        let a = project.appendingPathComponent("Sources/App/A.swift").path
        let b = project.appendingPathComponent("Sources/App/B.swift").path
        let old = Date(timeIntervalSince1970: 946_684_800)

        let first = try await factory.create(
            projectPath: project.path,
            schematizedFiles: [SchematizedFile(originalPath: a, schematizedContent: "schema a")]
        )
        let sandboxA = first.rootURL.appendingPathComponent("Sources/App/A.swift")
        let sandboxB = first.rootURL.appendingPathComponent("Sources/App/B.swift")
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: sandboxA.path)
        try first.cleanup()

        let second = try await factory.create(
            projectPath: project.path,
            schematizedFiles: [
                SchematizedFile(originalPath: a, schematizedContent: "schema a"),
                SchematizedFile(originalPath: b, schematizedContent: "schema b"),
            ]
        )
        #expect(try modificationDate(of: sandboxA) == old)
        #expect(try String(contentsOf: sandboxA, encoding: .utf8) == LintSuppression.wrapping("schema a"))
        #expect(try String(contentsOf: sandboxB, encoding: .utf8) == LintSuppression.wrapping("schema b"))
        try second.cleanup()

        let third = try await factory.create(
            projectPath: project.path,
            schematizedFiles: [SchematizedFile(originalPath: a, schematizedContent: "schema a2")]
        )
        defer { try? third.cleanup() }
        #expect(try String(contentsOf: sandboxA, encoding: .utf8) == LintSuppression.wrapping("schema a2"))
        #expect(try modificationDate(of: sandboxA) != old)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: sandboxB.path).hasSuffix("/B.swift"))
    }

    @Test("Given a slot still held, when another sandbox is created, then it takes the next slot")
    func aHeldSlotIsNotShared() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let (project, factory) = try makeProject(in: dir)

        let first = try await factory.createClean(projectPath: project.path)
        defer { try? first.cleanup() }
        let second = try await factory.createClean(projectPath: project.path)
        defer { try? second.cleanup() }

        #expect(first.slot?.index == 0)
        #expect(second.slot?.index == 1)
        #expect(second.rootURL != first.rootURL)
    }

    @Test("Given no warm sandboxes, when a sandbox is created, then it is a throwaway one and cleanup removes it")
    func anEphemeralSandboxIsRemovedOnCleanup() async throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let (project, _) = try makeProject(in: dir)

        let sandbox = try await SandboxFactory().createClean(projectPath: project.path)
        #expect(!sandbox.isPersistent)
        try sandbox.cleanup()

        #expect(!FileManager.default.fileExists(atPath: sandbox.rootURL.path))
    }

    // MARK: - Private

    private func makeProject(in dir: URL) throws -> (URL, SandboxFactory) {
        let project = dir.appendingPathComponent("project")
        let sources = project.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try FileHelpers.write("let a = 1", named: "A.swift", in: sources)
        try FileHelpers.write("let b = 1", named: "B.swift", in: sources)
        try FileHelpers.write("// swift-tools-version: 6.0", named: "Package.swift", in: project)
        return (project, SandboxFactory(warm: WarmSandboxes(directory: dir.appendingPathComponent("sandboxes"))))
    }

    private func modificationDate(of url: URL) throws -> Date? {
        try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}

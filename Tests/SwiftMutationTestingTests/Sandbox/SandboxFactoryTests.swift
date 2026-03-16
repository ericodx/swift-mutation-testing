import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("SandboxFactory")
struct SandboxFactoryTests {
    private let factory = SandboxFactory()

    @Test("Given schematized files, when sandbox created, then schematized content is written to sandbox")
    func writesSchematizedContent() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        try FileHelpers.write("original content", named: "File.swift", in: projectDir)
        let filePath = projectDir.appendingPathComponent("File.swift").path

        let schematized = SchematizedFile(originalPath: filePath, schematizedContent: "schematized content")
        let sandbox = try await factory.create(
            projectPath: projectDir.path,
            schematizedFiles: [schematized],
            supportFileContent: ""
        )
        defer { try? sandbox.cleanup() }

        let content = try String(
            contentsOf: sandbox.rootURL.appendingPathComponent("File.swift"),
            encoding: .utf8
        )

        #expect(content == "schematized content")
    }

    @Test("Given support file content and Sources directory, when sandbox created, then __SMTSupport.swift is written")
    func injectsSupportFileIntoSourcesDirectory() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        let sourcesDir = projectDir.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        try FileHelpers.write("original content", named: "File.swift", in: sourcesDir)
        let filePath = sourcesDir.appendingPathComponent("File.swift").path

        let schematized = SchematizedFile(originalPath: filePath, schematizedContent: "schematized content")
        let sandbox = try await factory.create(
            projectPath: projectDir.path,
            schematizedFiles: [schematized],
            supportFileContent: "let support = true"
        )
        defer { try? sandbox.cleanup() }

        let supportURL = sandbox.rootURL.appendingPathComponent("Sources/__SMTSupport.swift")
        let content = try String(contentsOf: supportURL, encoding: .utf8)

        #expect(content == "let support = true")
    }

    @Test("Given xcodeproj directory, when sandbox created, then xcuserdata is empty directory not a symlink")
    func xcodeprojXcuserdataIsEmptyDirectory() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        let xcuserdataDir =
            projectDir
            .appendingPathComponent("App.xcodeproj/xcuserdata")
        try FileManager.default.createDirectory(at: xcuserdataDir, withIntermediateDirectories: true)
        try FileHelpers.write("user data", named: "user.xcuserdatad", in: xcuserdataDir)

        let sandbox = try await factory.create(
            projectPath: projectDir.path,
            schematizedFiles: [],
            supportFileContent: ""
        )
        defer { try? sandbox.cleanup() }

        let sandboxXcuserdata = sandbox.rootURL.appendingPathComponent("App.xcodeproj/xcuserdata")
        let isSymlink = (try? sandboxXcuserdata.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
        let userDataFile = sandboxXcuserdata.appendingPathComponent("user.xcuserdatad")

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: sandboxXcuserdata.path, isDirectory: &isDir)

        #expect(exists == true)
        #expect(isDir.boolValue == true)
        #expect(isSymlink == false)
        #expect(FileManager.default.fileExists(atPath: userDataFile.path) == false)
    }

    @Test("Given file not in schematized list, when sandbox created, then file is a symlink to the original")
    func nonSchematizedFileIsSymlink() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        try FileHelpers.write("original content", named: "Unchanged.swift", in: projectDir)

        let sandbox = try await factory.create(
            projectPath: projectDir.path,
            schematizedFiles: [],
            supportFileContent: ""
        )
        defer { try? sandbox.cleanup() }

        let sandboxFile = sandbox.rootURL.appendingPathComponent("Unchanged.swift")
        let isSymlink = (try? sandboxFile.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
        let content = try String(contentsOf: sandboxFile, encoding: .utf8)

        #expect(isSymlink == true)
        #expect(content == "original content")
    }

    @Test("Given mutated file path and content, when single-file sandbox created, then mutated content is written")
    func writesMutatedContentInSingleFileSandbox() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        try FileHelpers.write("original content", named: "File.swift", in: projectDir)
        let filePath = projectDir.appendingPathComponent("File.swift").path

        let sandbox = try await factory.create(
            projectPath: projectDir.path,
            mutatedFilePath: filePath,
            mutatedContent: "mutated content"
        )
        defer { try? sandbox.cleanup() }

        let content = try String(
            contentsOf: sandbox.rootURL.appendingPathComponent("File.swift"),
            encoding: .utf8
        )

        #expect(content == "mutated content")
    }

    @Test("Given created sandbox, when cleanup called, then sandbox directory no longer exists")
    func cleanupRemovesSandboxDirectory() async throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        let sandbox = try await factory.create(
            projectPath: projectDir.path,
            schematizedFiles: [],
            supportFileContent: ""
        )

        try sandbox.cleanup()

        #expect(FileManager.default.fileExists(atPath: sandbox.rootURL.path) == false)
    }
}

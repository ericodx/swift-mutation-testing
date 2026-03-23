import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("TestFilesHasher")
struct TestFilesHasherTests {
    @Test("Given a project directory, when hash called, then a 64-character hex string is returned")
    func hashReturnsHexString() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let result = TestFilesHasher().hash(projectPath: dir.path)

        #expect(result.count == 64)
        #expect(result.allSatisfy { $0.isHexDigit })
    }

    @Test("Given the same project directory, when hash called twice, then identical hashes are returned")
    func hashIsDeterministic() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        try FileHelpers.write("let x = 1", named: "FooTests.swift", in: testsDir)

        let hasher = TestFilesHasher()
        #expect(hasher.hash(projectPath: dir.path) == hasher.hash(projectPath: dir.path))
    }

    @Test("Given a test file is modified, when hash called, then a different hash is returned")
    func hashChangesWhenTestFileContentChanges() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        let testFile = testsDir.appendingPathComponent("FooTests.swift")

        try "let x = 1".write(to: testFile, atomically: true, encoding: .utf8)
        let hashBefore = TestFilesHasher().hash(projectPath: dir.path)

        try "let x = 2".write(to: testFile, atomically: true, encoding: .utf8)
        let hashAfter = TestFilesHasher().hash(projectPath: dir.path)

        #expect(hashBefore != hashAfter)
    }

    @Test("Given only non-test swift files exist, when hash called, then same hash as empty project")
    func hashIgnoresNonTestSwiftFiles() throws {
        let empty = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(empty) }

        let withSources = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(withSources) }

        let sourcesDir = withSources.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        try FileHelpers.write("let x = 1", named: "Foo.swift", in: sourcesDir)

        let hasher = TestFilesHasher()
        #expect(hasher.hash(projectPath: empty.path) == hasher.hash(projectPath: withSources.path))
    }
}

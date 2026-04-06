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

    @Test("Given non-existent project path, when hash called, then returns a valid hash for empty content")
    func hashReturnsValidHashForNonExistentPath() {
        let result = TestFilesHasher().hash(projectPath: "/nonexistent/path/xyz")
        #expect(result.count == 64)
        #expect(result.allSatisfy { $0.isHexDigit })
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

    @Test("Given multiple test files, when hashPerFile called, then one entry per test file is returned")
    func hashPerFileReturnsOneEntryPerTestFile() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        try FileHelpers.write("let a = 1", named: "FooTests.swift", in: testsDir)
        try FileHelpers.write("let b = 2", named: "BarTests.swift", in: testsDir)

        let result = TestFilesHasher().hashPerFile(projectPath: dir.path)

        #expect(result.count == 2)
        #expect(result.keys.contains("Tests/FooTests.swift"))
        #expect(result.keys.contains("Tests/BarTests.swift"))
    }

    @Test("Given a test file is modified, when hashPerFile called, then only that file's hash changes")
    func hashPerFileChangesOnlyForModifiedFile() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        try FileHelpers.write("let a = 1", named: "FooTests.swift", in: testsDir)
        try FileHelpers.write("let b = 2", named: "BarTests.swift", in: testsDir)

        let before = TestFilesHasher().hashPerFile(projectPath: dir.path)

        try FileHelpers.write("let a = 999", named: "FooTests.swift", in: testsDir)

        let after = TestFilesHasher().hashPerFile(projectPath: dir.path)

        #expect(before["Tests/FooTests.swift"] != after["Tests/FooTests.swift"])
        #expect(before["Tests/BarTests.swift"] == after["Tests/BarTests.swift"])
    }

    @Test("Given non-test files exist, when hashPerFile called, then they are excluded")
    func hashPerFileExcludesNonTestFiles() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourcesDir = dir.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        try FileHelpers.write("let x = 1", named: "Foo.swift", in: sourcesDir)

        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        try FileHelpers.write("let t = 1", named: "FooTests.swift", in: testsDir)

        let result = TestFilesHasher().hashPerFile(projectPath: dir.path)

        #expect(result.count == 1)
        #expect(result.keys.contains("Tests/FooTests.swift"))
    }

    @Test("Given non-existent path, when hashPerFile called, then empty map is returned")
    func hashPerFileReturnsEmptyForNonExistentPath() {
        let result = TestFilesHasher().hashPerFile(projectPath: "/nonexistent/path/xyz")

        #expect(result.isEmpty)
    }
}

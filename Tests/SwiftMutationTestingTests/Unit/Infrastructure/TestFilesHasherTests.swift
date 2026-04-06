import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("TestFilesHasher")
struct TestFilesHasherTests {

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

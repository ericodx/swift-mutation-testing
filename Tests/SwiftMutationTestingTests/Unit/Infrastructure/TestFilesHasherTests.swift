import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("TestFilesHasher")
struct TestFilesHasherTests {

    @Test("Given multiple test files, when the test files are hashed, then one entry per test file is returned")
    func hashingReturnsOneEntryPerTestFile() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        try FileHelpers.write("let a = 1", named: "FooTests.swift", in: testsDir)
        try FileHelpers.write("let b = 2", named: "BarTests.swift", in: testsDir)

        let result = TestFilesHasher().snapshot(projectPath: dir.path).hashes

        #expect(result.count == 2)
        #expect(result.keys.contains("Tests/FooTests.swift"))
        #expect(result.keys.contains("Tests/BarTests.swift"))
    }

    @Test("Given a test file is modified, when the test files are hashed, then only that file's hash changes")
    func hashingChangesOnlyForModifiedFile() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        try FileHelpers.write("let a = 1", named: "FooTests.swift", in: testsDir)
        try FileHelpers.write("let b = 2", named: "BarTests.swift", in: testsDir)

        let before = TestFilesHasher().snapshot(projectPath: dir.path).hashes

        try FileHelpers.write("let a = 999", named: "FooTests.swift", in: testsDir)

        let after = TestFilesHasher().snapshot(projectPath: dir.path).hashes

        #expect(before["Tests/FooTests.swift"] != after["Tests/FooTests.swift"])
        #expect(before["Tests/BarTests.swift"] == after["Tests/BarTests.swift"])
    }

    @Test("Given non-test files exist, when the test files are hashed, then they are excluded")
    func hashingExcludesNonTestFiles() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourcesDir = dir.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        try FileHelpers.write("let x = 1", named: "Foo.swift", in: sourcesDir)

        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        try FileHelpers.write("let t = 1", named: "FooTests.swift", in: testsDir)

        let result = TestFilesHasher().snapshot(projectPath: dir.path).hashes

        #expect(result.count == 1)
        #expect(result.keys.contains("Tests/FooTests.swift"))
    }

    @Test("Given a test file outside Tests and a helper inside it, when hashed, then both are hashed")
    func hashingTakesEitherATestsDirectoryOrATestsSuffix() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let sourcesDir = dir.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        try FileHelpers.write("let t = 1", named: "InlineTests.swift", in: sourcesDir)

        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        try FileHelpers.write("let h = 1", named: "Helpers.swift", in: testsDir)

        let result = TestFilesHasher().snapshot(projectPath: dir.path).hashes

        #expect(Set(result.keys) == ["Sources/InlineTests.swift", "Tests/Helpers.swift"])
    }

    @Test("Given test file symlinked outside project, when hashed, then absolute path is used as key")
    func hashingUsesAbsolutePathForExternalSymlink() throws {
        let projectDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(projectDir) }

        let externalDir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(externalDir) }

        try FileHelpers.write("let t = 1", named: "ExternalTests.swift", in: externalDir)

        let testsDir = projectDir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        let symlinkURL = testsDir.appendingPathComponent("ExternalTests.swift")
        let targetURL = externalDir.appendingPathComponent("ExternalTests.swift")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: targetURL)

        let result = TestFilesHasher().snapshot(projectPath: projectDir.path).hashes

        #expect(result.count == 1)
        let key = result.keys.first!
        #expect(!key.hasPrefix("Tests/"))
    }

    @Test("Given non-existent path, when the test files are hashed, then empty map is returned")
    func hashingReturnsEmptyForNonExistentPath() {
        let result = TestFilesHasher().snapshot(projectPath: "/nonexistent/path/xyz").hashes

        #expect(result.isEmpty)
    }

    @Test("Given a Swift file that is not text, when hashing, then it is left out instead of failing the run")
    func aFileThatIsNotTextIsLeftOut() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let tests = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try "import Testing".write(
            to: tests.appendingPathComponent("GoodTests.swift"), atomically: true, encoding: .utf8
        )
        try Data([0xFF, 0xFE, 0x00, 0x80]).write(to: tests.appendingPathComponent("BadTests.swift"))

        let hashes = TestFilesHasher().snapshot(projectPath: dir.path).hashes

        #expect(hashes.keys.contains { $0.hasSuffix("GoodTests.swift") })
        #expect(!hashes.keys.contains { $0.hasSuffix("BadTests.swift") })
    }

    @Test("Given a project path that does not exist, when listing test files, then the list is empty")
    func aMissingProjectPathListsNothing() {
        #expect(TestFilesHasher().snapshot(projectPath: "/does/not/exist").paths.isEmpty)
    }

    @Test("Given a directory that cannot be enumerated, when listing or hashing, then both come back empty")
    func aDirectoryThatCannotBeEnumeratedYieldsNothing() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let tests = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try "import Testing".write(
            to: tests.appendingPathComponent("RealTests.swift"), atomically: true, encoding: .utf8
        )
        let hasher = TestFilesHasher()

        #expect(!hasher.snapshot(projectPath: dir.path).paths.isEmpty)
        #expect(hasher.snapshot(projectPath: dir.path, enumerate: { _ in nil }).paths.isEmpty)
        #expect(hasher.snapshot(projectPath: dir.path, enumerate: { _ in nil }).hashes.isEmpty)
    }

    @Test("Given a project inside a directory named like a test target, when listing test files, then sources stay out")
    func aParentNamedLikeATestTargetIsIgnored() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let project = dir.appendingPathComponent("IntegrationTests/App")
        let sources = project.appendingPathComponent("Sources")
        let tests = project.appendingPathComponent("Tests/AppTests")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try FileHelpers.write("let a = 1", named: "Calc.swift", in: sources)
        try FileHelpers.write("let b = 2", named: "Helpers.swift", in: tests)

        let result = TestFilesHasher().snapshot(projectPath: project.path).hashes

        #expect(result.keys.sorted() == ["Tests/AppTests/Helpers.swift"])
    }

    @Test("Given test files, when a snapshot is taken, then it lists every one and holds the readable ones")
    func aSnapshotListsEveryFileAndHoldsTheReadableOnes() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }
        let tests = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        let good = tests.appendingPathComponent("GoodTests.swift")
        let bad = tests.appendingPathComponent("BadTests.swift")
        try "import Testing".write(to: good, atomically: true, encoding: .utf8)
        try Data([0xFF, 0xFE, 0x00, 0x80]).write(to: bad)

        let snapshot = TestFilesHasher().snapshot(projectPath: dir.path)

        #expect(snapshot.paths.count == 2)
        #expect(snapshot.contents.values.sorted() == ["import Testing"])
        #expect(snapshot.contents.keys.allSatisfy { $0.hasSuffix("GoodTests.swift") })
        #expect(snapshot.hashes.keys.sorted() == ["Tests/GoodTests.swift"])
    }
}

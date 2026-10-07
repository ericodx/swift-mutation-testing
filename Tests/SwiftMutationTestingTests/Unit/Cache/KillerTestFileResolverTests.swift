import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("KillerTestFileResolver")
struct KillerTestFileResolverTests {
    @Test("Given XCTest class name, when resolved, then returns file matching class name")
    func resolvesXCTestClassName() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        let filePath = testsDir.appendingPathComponent("CalculatorTests.swift").path
        try "import XCTest".write(toFile: filePath, atomically: true, encoding: .utf8)

        let resolver = KillerTestFileResolver(testFilePaths: [filePath], projectPath: dir.path)

        let result = resolver.resolve(testName: "CalculatorTests.testAddition")

        #expect(result == "Tests/CalculatorTests.swift")
    }

    @Test("Given XCTest three-part name, when resolved, then returns file matching middle component")
    func resolvesXCTestThreePartName() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        let filePath = testsDir.appendingPathComponent("CalculatorTests.swift").path
        try "import XCTest".write(toFile: filePath, atomically: true, encoding: .utf8)

        let resolver = KillerTestFileResolver(testFilePaths: [filePath], projectPath: dir.path)

        let result = resolver.resolve(testName: "MyModule.CalculatorTests.testAddition")

        #expect(result == "Tests/CalculatorTests.swift")
    }

    @Test("Given Swift Testing function name, when resolved, then returns file containing function")
    func resolvesSwiftTestingFunctionName() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        let filePath = testsDir.appendingPathComponent("MathTests.swift").path
        try "func testAddition() { }".write(toFile: filePath, atomically: true, encoding: .utf8)

        let resolver = KillerTestFileResolver(testFilePaths: [filePath], projectPath: dir.path)

        let result = resolver.resolve(testName: "MyModule/MathTests/testAddition")

        #expect(result == "Tests/MathTests.swift")
    }

    @Test("Given a test file outside the project, when resolved, then the path is returned unchanged")
    func returnsPathOutsideProjectUnchanged() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let filePath = dir.appendingPathComponent("CalculatorTests.swift").path
        try "import XCTest".write(toFile: filePath, atomically: true, encoding: .utf8)

        let resolver = KillerTestFileResolver(testFilePaths: [filePath], projectPath: "/somewhere/else")

        let result = resolver.resolve(testName: "CalculatorTests.testAddition")

        #expect(result == filePath)
    }

    @Test("Given unknown test name, when resolved, then returns nil")
    func returnsNilForUnknownTestName() {
        let resolver = KillerTestFileResolver(testFilePaths: ["/some/path/FooTests.swift"], projectPath: "/some")

        let result = resolver.resolve(testName: "UnknownTests.testSomething")

        #expect(result == nil)
    }

    @Test("Given empty test file paths, when resolved, then returns nil")
    func returnsNilWhenNoTestFiles() {
        let resolver = KillerTestFileResolver(testFilePaths: [], projectPath: "/tmp")

        let result = resolver.resolve(testName: "SomeTests.testMethod")

        #expect(result == nil)
    }

    @Test("Given a resolved killer file, when hashed by TestFilesHasher, then both agree on the form")
    func resolvedPathMatchesHasherKeys() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let testsDir = dir.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        try "import XCTest".write(
            toFile: testsDir.appendingPathComponent("CalculatorTests.swift").path,
            atomically: true,
            encoding: .utf8
        )

        let hasher = TestFilesHasher()
        let resolver = KillerTestFileResolver(
            testFilePaths: hasher.testFilePaths(projectPath: dir.path),
            projectPath: dir.path
        )

        let killerFile = try #require(resolver.resolve(testName: "CalculatorTests.testAddition"))
        let hashedKeys = Set(hasher.hashPerFile(projectPath: dir.path).keys)

        #expect(hashedKeys.contains(killerFile), "\(killerFile) is not among \(hashedKeys)")
    }

    @Test("Given an empty test name, when resolved, then no file is named")
    func anEmptyTestNameResolvesToNothing() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let filePath = dir.appendingPathComponent("SomeTests.swift").path
        try "import Testing".write(toFile: filePath, atomically: true, encoding: .utf8)

        let resolver = KillerTestFileResolver(testFilePaths: [filePath], projectPath: dir.path)

        #expect(resolver.resolve(testName: "") == nil)
    }

    @Test("Given a test reported by its title, when resolved, then the file whose @Test has that title is named")
    func aTestTitleNamesItsFile() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let filePath = dir.appendingPathComponent("TitleTests.swift").path
        try #"@Test("adds \"two\" numbers") func somethingElse() {}"#
            .write(toFile: filePath, atomically: true, encoding: .utf8)

        let resolver = KillerTestFileResolver(testFilePaths: [filePath], projectPath: dir.path)

        #expect(resolver.resolve(testName: #"adds \"two\" numbers"#) == "TitleTests.swift")
    }

    @Test("Given the name appears only inside another test's title, when resolved, then no file is named")
    func aNameInsideAnotherTitleNamesNothing() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let filePath = dir.appendingPathComponent("TitleTests.swift").path
        try #"@Test("covers aCheck") func somethingElse() {}"#
            .write(toFile: filePath, atomically: true, encoding: .utf8)

        let resolver = KillerTestFileResolver(testFilePaths: [filePath], projectPath: dir.path)

        #expect(resolver.resolve(testName: "TitleTests/aCheck") == nil)
    }

    @Test("Given one file that calls a test function and one that declares it, when resolved, then the declaring one")
    func theDeclaringFileWinsOverACaller() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let caller = dir.appendingPathComponent("ACallerTests.swift").path
        let declarer = dir.appendingPathComponent("ZDeclarerTests.swift").path
        try "@Test func other() { aCheck(value: 1) }".write(toFile: caller, atomically: true, encoding: .utf8)
        try "@Test func aCheck(value: Int) {}".write(toFile: declarer, atomically: true, encoding: .utf8)

        let resolver = KillerTestFileResolver(testFilePaths: [caller, declarer], projectPath: dir.path)

        #expect(resolver.resolve(testName: "aCheck(value:)") == "ZDeclarerTests.swift")
    }

    @Test("Given many kills, when they are resolved, then each test file is read only once")
    func everyFileIsReadOnce() {
        let reads = ReadCounter()
        let resolver = KillerTestFileResolver(
            testFilePaths: ["/p/ATests.swift", "/p/BTests.swift"], projectPath: "/p",
            read: { path in reads.count(path) }
        )

        for _ in 0 ..< 50 {
            _ = resolver.resolve(testName: "bCheck()")
            _ = resolver.resolve(testName: "missing()")
        }

        #expect(resolver.resolve(testName: "bCheck()") == "BTests.swift")
        #expect(reads.paths == ["/p/ATests.swift", "/p/BTests.swift"])
    }

    @Test("Given no test file mentions the name, when resolved, then no file is named")
    func aNameNoFileMentionsResolvesToNothing() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let filePath = dir.appendingPathComponent("OtherTests.swift").path
        try "import Testing".write(toFile: filePath, atomically: true, encoding: .utf8)

        let resolver = KillerTestFileResolver(testFilePaths: [filePath], projectPath: dir.path)

        #expect(resolver.resolve(testName: "OtherTests/missingCheck") == nil)
    }
}

private final class ReadCounter: @unchecked Sendable {
    private(set) var paths: [String] = []

    func count(_ path: String) -> String {
        paths.append(path)
        return path.hasSuffix("BTests.swift") ? "@Test func bCheck() {}" : "@Test func aCheck() {}"
    }
}
